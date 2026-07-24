#!/bin/bash


read -p "Введіть ім'я профілю: " PROFILE_NAME
read -p "Введіть назва маршрута: " NAME
read -p "Введіть які номери, або пул номерів (згідно регулярних виразів): " NUMBER
read -p "Введіть назву транку: " GATEWAY

# Шляхи до конфігів FreeSWITCH за замовчуванням
FS_DIR="/etc/freeswitch/dialplan/$PROFILE_NAME"


# Кольори для виводу в термінал
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}[1/4] Перевірка та створення необхідних директорій...${NC}"
mkdir -p "$FS_DIR"

# ====================================================================
# ЧАСТИНА 1: СТВОРЕННЯ EXTENSIONS (АБОНЕНТІВ)
# ====================================================================
echo -e "${BLUE}[2/4] Генерація конфігурацій...${NC}"

# Створюємо абонента 1001
cat << EOF > "$FS_DIR/$NAME.xml"
<include>
  <extension name="$NAME">
    <condition field="destination_number" expression="^($NUMBER)$">
        <action application="set" data="hangup_after_bridge=true"/>
        <action application="set" data="continue_on_fail=true"/>
        <action application="bridge" data="sofia/gateway/$GATEWAY/\$1"/>
        <action application="hangup"/>
    </condition>
  </extension>
</include>
EOF

fs_cli -x "reloadxml"
