#!/bin/bash

read -p "Введіть ім'я профілю: " PROFILE_NAME
read -p "Введіть бажаний номер: " NUMBER
read -p "Введіть бажаний пароль: " PASSWORD

# Шляхи до конфігів FreeSWITCH за замовчуванням
FS_DIR="/etc/freeswitch/directory/$PROFILE_NAME"


# Кольори для виводу в термінал
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}[1/4] Перевірка та створення необхідних директорій...${NC}"
mkdir -p "$FS_DIR"

# ====================================================================
# ЧАСТИНА 1: СТВОРЕННЯ EXTENSIONS (АБОНЕНТІВ)
# ====================================================================
echo -e "${BLUE}[2/4] Генерація конфігурацій для абонента $NUMBER...${NC}"

# Створюємо абонента 1001
cat << EOF > "$FS_DIR/$NUMBER.xml"
<include>
  <user id="$NUMBER">
    <params>
      <param name="password" value="$PASSWORD"/>
    </params>
    <variables>
      <variable name="number_alias" value="$NUMBER"/>
      <variable name="effective_caller_id_name" value="$NUMBER"/>
      <variable name="effective_caller_id_number" value="$NUMBER"/>
      <variable name="outbound_caller_id_name" value="$NUMBER"/>
      <variable name="outbound_caller_id_number" value="$NUMBER"/>
      <variable name="user_context" value="$PROFILE_NAME"/>
      <variable name="sip-force-expires" value="3600"/>
      <variable name="dtmf-type" value="rfc2833"/>
    </variables>
  </user>
</include>
EOF

fs_cli -x "reloadxml"