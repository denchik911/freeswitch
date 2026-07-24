#!/bin/bash


read -p "Введіть ім'я профілю: " PROFILE_NAME
read -p "Введіть назва маршрута: " NAME
read -p "Введіть які номери, або пул номерів (згідно регулярних виразів): " NUMBER
read -p "Введіть внутрішній домен або IP сервера: " DOMAIN

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
  <extension name="${NAME}">
    <condition field="destination_number" expression="^(${NUMBER})\$">
         <action application="bridge" data="user/\$1@${DOMAIN}"/>
        <!-- Кладем трубку -->
        <action application="hangup"/>
    </condition>
  </extension>
</include>
EOF

fs_cli -x "reloadxml"
