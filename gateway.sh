#!/bin/bash

read -p "Введіть ім'я профілю: " PROFILE_NAME
read -p "Введіть назву транку: " NAME
read -p "Введіть IP адресу: " NETWORK
read -p "Введіть номер для реєстрації: " NUMBER
read -p "Введіть пароль для реєстрації: " PASSWORD

# Шляхи до конфігів FreeSWITCH за замовчуванням
FS_DIR="/etc/freeswitch/sip_profiles/$PROFILE_NAME"


# Кольори для виводу в термінал
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}[1/4] Перевірка та створення необхідних директорій...${NC}"
mkdir -p "$FS_DIR"

# ====================================================================
# ЧАСТИНА 1: СТВОРЕННЯ EXTENSIONS (АБОНЕНТІВ)
# ====================================================================
echo -e "${BLUE}[2/4] Генерація конфігурацій для транка...${NC}"

# Створюємо абонента 1001
cat << EOF > "$FS_DIR/$NAME.xml"
   <gateway name="${NAME}">
     <param name="username" value="${NUMBER}"/>
     <param name="password" value="${PASSWORD}"/>
     <param name="register" value="true"/>
     <param name="proxy" value="${NETWORK}"/>
     <param name="context" value="${PROFILE_NAME}"/>
   </gateway>
EOF

fs_cli -x "reloadxml"
