#!/bin/bash

set -e

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m' 

# Перевірка на запуск від імені root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Будь ласка, запустить скрипт від імені root (через sudo).${NC}"
  exit 1
fi

echo -e "${GREEN}====================================================${NC}"
# Інтерактивне введення змінних від користувача
read -p "Введіть ім'я профілю: " PROFILE_NAME
read -p "Введіть локальну IPv4 адресу вашого сервера: " LOCAL_IP

# Перевірка, чи не порожні значення
if [ -z "$PROFILE_NAME" ] || [ -z "$LOCAL_IP" ]; then
  echo "${RED}Помилка: ім'я профілю та IP-адреса не можуть бути порожніми!${NC}"
  exit 1
fi

FS_DIR="/etc/freeswitch"
echo -e "${GREEN}Починаємо налаштування FreeSWITCH для профілю: $PROFILE_NAME ($LOCAL_IP)...${NC}"
echo -e "${GREEN}====================================================${NC}"

# 1. Перезапуск демона та увімкнення сервісу
systemctl daemon-reload
systemctl enable freeswitch
systemctl restart freeswitch

# 2. Виключення дефолтних (непотрібних) профілів
echo -e "${RED}Очищення та відключення дефолтних профілів...${NC}"

mkdir -p ~/freeswitch/sip_profiles
mkdir -p ~/freeswitch/directory
mkdir -p ~/freeswitch/dialplan

# Якщо в папці є файли (зірочка розгортається), то переносимо їх
if [ -d "$FS_DIR/sip_profiles" ] && [ "$(ls -A "$FS_DIR/sip_profiles")" ]; then
    mv "$FS_DIR/sip_profiles/"* ~/freeswitch/sip_profiles/ || exit 1
fi

if [ -d "$FS_DIR/directory" ] && [ "$(ls -A "$FS_DIR/directory")" ]; then
    mv "$FS_DIR/directory/"* ~/freeswitch/directory/ || exit 1
fi

if [ -d "$FS_DIR/dialplan" ] && [ "$(ls -A "$FS_DIR/dialplan")" ]; then
    mv "$FS_DIR/dialplan/"* ~/freeswitch/dialplan/ || exit 1
fi



# 3. Відключення модулів VERTO та Signalwire
echo -e "${GREEN}Налаштування модулів (modules.conf.xml)...${NC}"

MOD_CONF="$FS_DIR/autoload_configs/modules.conf.xml"

if [ -f "$MOD_CONF" ]; then

    # mod_verto -> коментуємо
    sed -i 's|<load module="mod_verto"/>|<!-- <load module="mod_verto"/> -->|g' "$MOD_CONF"
    # mod_signalwire -> коментуємо
    sed -i 's|<load module="mod_signalwire"/>|<!-- <load module="mod_signalwire"/> -->|g' "$MOD_CONF"

fi

# Налаштування acl для websocket та eventsocket
echo -e "${GREEN}Налаштування acl.conf.xml...${NC}"

ACL_CONF="$FS_DIR/autoload_configs/acl.conf.xml"

if [ -f "$ACL_CONF" ] && ! grep -q 'name="event_socket"' "$ACL_CONF"; then
    sed -i '/<network-lists>/a\
\
    <list name="internal_networks" default="deny">\
      <node type="allow" cidr="10.0.0.0/8"/>\
    </list>\
\
    <list name="event_socket" default="deny">\
      <node type="allow" cidr="10.0.0.0/8"/>\
      <node type="allow" cidr="127.0.0.1/16"/>\
    </list>\
' "$ACL_CONF"
fi


# 4. Налаштування mod_event_socket (IPv4)
echo -e "${GREEN}Налаштування event_socket.conf.xml...${NC}"
ES_CONF="$FS_DIR/autoload_configs/event_socket.conf.xml"
if [ -f "$ES_CONF" ]; then
    sed -i 's|name="listen-ip" value="::"|name="listen-ip" value="0.0.0.0"|g' "$ES_CONF"
    sed -i 's|<!--<param name="apply-inbound-acl" value="loopback.auto"/>-->|<param name="apply-inbound-acl" value="event_socket"/>|g' "$ES_CONF"
fi

# 5. Відкриття портів RTP в діапазоні 8000 – 32768
echo -e "${GREEN}Налаштування діапазону RTP портів...${NC}"
SWITCH_CONF="$FS_DIR/autoload_configs/switch.conf.xml"
if [ -f "$SWITCH_CONF" ]; then
    # Використовуємо sed для заміни значень портів
    sed -i 's|<!-- <param name="rtp-start-port" value=".*"/> -->|<param name="rtp-start-port" value="8000"/>|g' "$SWITCH_CONF"
    sed -i 's|<!-- <param name="rtp-end-port" value=".*"/> -->|<param name="rtp-end-port" value="32768"/>|g' "$SWITCH_CONF"
fi

# Встановлення net-tools для діагностики (за бажанням)
apt-get update && apt-get install -y net-tools tcpdump sngrep mc

# 6. Зміна глобальних змінних у vars.xml
echo -e "${GREEN}Редагування vars.xml...${NC}"

cp $FS_DIR/vars.xml ~/freeswitch/

VARS_CONF="$FS_DIR/vars.xml"
if [ -f "$VARS_CONF" ]; then
    # Зміна дефолтного паролю
    sed -i 's|data="default_password=1234"|data="default_password=12345678"|g' "$VARS_CONF"
    # Прописування локального IP
    sed -i '/local_ip_v4=/d' "$VARS_CONF"
    sed -i "/domain=\$\${local_ip_v4}/i <X-PRE-PROCESS cmd=\"set\" data=\"local_ip_v4=$LOCAL_IP\"/>" "$VARS_CONF"
    # Зміна профіля
    sed -i "s|<X-PRE-PROCESS cmd=\"set\" data=\"use_profile=.*\"/>|<X-PRE-PROCESS cmd=\"set\" data=\"use_profile=$PROFILE_NAME\"/>|g" "$VARS_CONF"
    # Коментування stun-set
    sed -i 's|<X-PRE-PROCESS cmd="stun-set" data="external_rtp_ip=stun:stun.freeswitch.org"/>|<!-- <X-PRE-PROCESS cmd="stun-set" data="external_rtp_ip=stun:stun.freeswitch.org"/> -->|g' "$VARS_CONF"
fi

SOFIA_CONF="$FS_DIR/autoload_configs/sofia.conf.xml"
if [ -f "$SOFIA_CONF" ]; then
    sed -i "s|<!-- <param name=\"capture-server\" value=\"udp:homer.domain.com:5060;hep=3;capture_id=100\"/> -->|<param name=\"capture-server\" value=\"udp:${LOCAL_IP}:9060;hep=3;capture_id=100\"/>|g" "$SOFIA_CONF"
fi

# 7. Налаштування запису логів у файл
echo -e "${GREEN}Налаштування логування...${NC}"
touch /var/log/freeswitch.log
chown freeswitch:freeswitch /var/log/freeswitch.log
chown freeswitch:freeswitch /var/log/

LOG_CONF="$FS_DIR/autoload_configs/logfile.conf.xml"
if [ -f "$LOG_CONF" ]; then
    sed -i 's|<!-- <param name="logfile" value="/var/log/freeswitch.log"/> -->|<param name="logfile" value="/var/log/freeswitch.log"/>|g' "$LOG_CONF"
fi

# 8. Створення нового SIP профілю
echo -e "${GREEN}Створення SIP профілю: $PROFILE_NAME.xml ...${NC}"
cat <<EOF > "$FS_DIR/sip_profiles/${PROFILE_NAME}.xml"
<profile name="${PROFILE_NAME}">
  <gateways>
    <X-PRE-PROCESS cmd="include" data="${PROFILE_NAME}/*.xml"/>
  </gateways>
  <aliases>
  </aliases>
  <domains>
    <domain name="all" alias="false" parse="true"/>
  </domains>
  <settings>
    <param name="apply-candidate-acl" value="internal_networks"/>
    <param name="rtp-secure-media" value="optional"/>
    <param name="media-webrtc" value="true"/>
    <param name="wss-binding" value=":7443"/>
    <param name="dtls-cert-dir" value="/etc/freeswitch/tls"/>
    <param name="user-agent-string" value="FreeSWITCH ${PROFILE_NAME}"/>
    <param name="caller-id-type" value="rpid"/>
    <param name="debug" value="7"/>
    <param name="sip-trace" value="no"/>
    <param name="sip-capture" value="no"/>
    <param name="log-auth-failures" value="true"/>
    <param name="rfc2833-pt" value="101"/>
    <param name="dtmf-duration" value="2000"/>
    <param name="dtmf-type" value="rfc2833"/>
    <param name="liberal-dtmf" value="true"/>
    <param name="watchdog-enabled" value="false"/>
    <param name="sip-port" value="5060"/>
    <param name="sip-ip" value="\$\${local_ip_v4}"/>
    <param name="rtp-ip" value="\$\${local_ip_v4}"/>
    <param name="nonce-ttl" value="60"/>
    <param name="ext-rtp-ip" value="auto-nat"/>
    <param name="ext-sip-ip" value="auto-nat"/>
    <param name="dialplan" value="XML"/>
    <param name="context" value="${PROFILE_NAME}"/>
    <param name="max-proceeding" value="2000"/>
    <param name="hold-music" value="\$\${hold_music}"/>
    <param name="all-reg-options-ping" value="true"/>
    <param name="nat-options-ping" value="true"/>
    <param name="unregister-on-options-fail" value="true"/>
    <param name="sip-options-respond-503-on-busy" value="true"/>
    <param name="auth-calls" value="true"/>
    <param name="inbound-reg-force-matching-username" value="true"/>
    <param name="inbound-codec-prefs" value="PCMA,PCMU,h264"/>
    <param name="outbound-codec-prefs" value="PCMA,PCMU,h264"/>
    <param name="disable-transcoding" value="true"/>
    <param name="inbound-codec-negotiation" value="generous"/>
    <param name="inbound-late-negotiation" value="true"/>
    <param name="rtp-timer-name" value="soft"/>
    <param name="auto-jitterbuffer-msec" value="60"/>
    <param name="rtp-timeout-sec" value="300"/>
    <param name="rtp-hold-timeout-sec" value="1800"/>
    <param name="enable-timer" value="false"/>
    <param name="auth-all-packets" value="false"/>
    <param name="enable-100rel" value="true"/>
    <param name="challenge-realm" value="auto_from"/>
    <param name="manage-presence" value="true"/>
    <param name="accept-blind-auth" value="false"/>
    <param name="accept-blind-reg" value="false"/>
    <param name="sip-capture" value="yes"/>
    <param name="capture-server" value="udp:${LOCAL_IP}:9060"/>
    <param name="capture-id" value="3"/>
  </settings>
</profile>
EOF

mkdir -p "$FS_DIR/sip_profiles/${PROFILE_NAME}"

# 9. Створення опису абонентів (Directory)


echo -e "${GREEN}Налаштування Directory (користувачі)...${NC}"
cat <<EOF > "$FS_DIR/directory/${PROFILE_NAME}.xml"
<include>
  <domain name="\$\${local_ip_v4}">
    <params>
        <param name="dial-string" value="{presence_id=\${dialed_user}@\${dialed_domain}}\${sofia_contact(\${dialed_user}@\${dialed_domain})}"/>
    </params>
    <variables>
      <variable name="record_stereo" value="true"/>
    </variables>
    <groups>
      <group name="${PROFILE_NAME}">
        <users>
          <X-PRE-PROCESS cmd="include" data="${PROFILE_NAME}/*.xml"/>
        </users>
      </group>
    </groups>
  </domain>
</include>
EOF

mkdir -p "$FS_DIR/directory/${PROFILE_NAME}"

# 10. Створення внутрішнього плану набору (Dialplan)
echo -e "${GREEN}Налаштування Dialplan...${NC}"
cat <<EOF > "$FS_DIR/dialplan/${PROFILE_NAME}.xml"
<include>
  <context name="${PROFILE_NAME}">

    <!-- ========================================================= -->
    <!--  GLOBAL ENTRY POINT                                       -->
    <!-- ========================================================= -->

    <extension name="00_global_entry">

      <!-- Ловимо всі числові номери -->
      <condition field="destination_number" expression="^(\d+)$">

        <!-- ===================================================== -->
        <!--  1. TRACE / CORRELATION ID                           -->
        <!--  Використовується для логів, Homer, billing         -->
        <!-- ===================================================== -->
        <action application="set" data="trace_id=\${uuid}"/>
        <action application="set" data="call_uuid=\${uuid}"/>
        <action application="set" data="call_start_epoch=\${epoch}"/>

        <!-- ===================================================== -->
        <!--  2. LOGGING LAYER                                    -->
        <!--  Тут ти бачиш ВСІ виклики                            -->
        <!-- ===================================================== -->
        <action application="log" data="INFO [\${trace_id}] CALL START to=\${destination_number} from=\${caller_id_number}"/>

        <!-- ===================================================== -->
        <!--  3. LOOP PROTECTION                                  -->
        <!--  Захист від SIP зациклення                           -->
        <!-- ===================================================== -->
        <condition field="\${sip_looped_call}" expression="^true$">
          <action application="log" data="WARNING [\${trace_id}] LOOP DETECTED to=\${destination_number}"/>
          <action application="set" data="hangup_after_bridge=true"/>
          <action application="hangup" data="CALL_REJECTED"/>
        </condition>

        <!-- ===================================================== -->
        <!--  4. NORMALIZATION LAYER                              -->
        <!--  Тут можна чистити номер (E.164, префікси і т.д.)    -->
        <!-- ===================================================== -->
        <action application="set" data="normalized_destination=\${destination_number}"/>
        <action application="set" data="effective_caller_id_number=\${caller_id_number}"/>

        <!-- ===================================================== -->
        <!--  5. SECURITY TAGS                                    -->
        <!--  Потім можна фільтрувати fraud / ACL                 -->
        <!-- ===================================================== -->
        <action application="set" data="security_checked=false"/>
        <action application="set" data="fraud_score=0"/>

        <!-- ===================================================== -->
        <!--  6. BILLING HOOK (майбутнє)                          -->
        <!--  Тут можна підключити білінг / CDR / API             -->
        <!-- ===================================================== -->
        <action application="set" data="billing_enabled=true"/>

        <!-- ===================================================== -->
        <!--  7. EXTERNAL INTEGRATION HOOK                        -->
        <!--  CRM / HTTP API / AI routing / SIP proxy             -->
        <!-- ===================================================== -->
        <action application="set" data="api_routing_enabled=false"/>

      </condition>

    </extension>
    <X-PRE-PROCESS cmd="include" data="${PROFILE_NAME}/*.xml"/>
  </context>
</include>
EOF

mkdir -p "$FS_DIR/dialplan/${PROFILE_NAME}"

# 13. Виставлення прав на файли та рестарт сервісу
echo -e "${GREEN}Виставлення прав доступу на папки FreeSWITCH...${NC}"
chown -R freeswitch:freeswitch "$FS_DIR/"
chmod -R 770 "$FS_DIR/"

echo -e  "${GREEN}Перезапуск сервісу FreeSWITCH...${NC}"
systemctl restart freeswitch

echo -e "${GREEN}====================================================${NC}"
echo -e " ${GREEN}Налаштування успішно завершено!${NC}"
echo -e " ${GREEN}Контекст та профіль '$PROFILE_NAME' створено.${NC}"
echo -e " ${GREEN}Перевірити статус профілів можна командою: fs_cli -x 'sofia status'${NC}"
echo -e " ${GREEN}Перевірити порти: netstat -ltupn | grep freesw${NC}"
echo -e "====================================================${NC}"
