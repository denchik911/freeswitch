#!/bin/bash

# Перевірка на запуск від імені root
if [ "$EUID" -ne 0 ]; then
  echo "Будь ласка, запустить скрипт від імені root (через sudo)."
  exit 1
fi


echo "=========================================================="
echo "   Встановлення та налаштування OpenSIPS Control Panel    "
echo "=========================================================="

OCP_DIR="/var/www/html/opensips-cp"
WEB_ROOT="/var/www/html"

echo "[INFO] Checking web root..."

if [ ! -d "$WEB_ROOT" ]; then
  echo "[INFO] Apache web root not found. Installing Apache..."

  apt update
  sudo apt install -y php php-curl php-gd php-mysql php-pear php-cli php-apcu libapache2-mod-php
  apt install apache2 -y

  mkdir -p "$WEB_ROOT"
  chown -R www-data:www-data "$WEB_ROOT"
fi

cd "$WEB_ROOT" || exit 1

echo "[INFO] Checking OpenSIPS CP..."

if [ ! -d "$OCP_DIR" ]; then
  echo "[INFO] Installing OpenSIPS CP..."

  git clone https://github.com/OpenSIPS/opensips-cp.git

  if [ $? -ne 0 ]; then
    echo "[ERROR] Clone failed"
    exit 1
  fi

  echo "[OK] OpenSIPS CP installed"
else
  echo "[OK] OpenSIPS CP already exists"
fi

# Визначення дистрибутиву (Debian-like чи RedHat-like)
if [ -f /etc/debian_version ]; then
    OS_TYPE="debian"
    WEB_USER="www-data"
    APACHE_CONF_DIR="/etc/apache2/conf-available"
    APACHE_SERVICE="apache2"
elif [ -f /etc/redhat-release ] || [ -f /etc/system-release ]; then
    OS_TYPE="redhat"
    WEB_USER="apache"
    APACHE_CONF_DIR="/etc/httpd/conf.d"
    APACHE_SERVICE="httpd"
else
    echo "Невідома операційна система. Скрипт підтримує лише Debian/RedHat сімейства."
    exit 1
fi

echo "Виявлено ОС сімейства: $OS_TYPE. Веб-користувач: $WEB_USER"
echo "----------------------------------------------------------"

# 1. Встановлення Apache, PHP та розширень
echo "Крок 1: Встановлення Apache та PHP з розширеннями..."
if [ "$OS_TYPE" == "debian" ]; then
    apt-get update
    apt-get install -y apache2 libapache2-mod-php php-curl php php-gd php-mysql php-pear php-cli php-apcu mysql-client
else
    yum install -y httpd php php-gd php-mysql php-xmlrpc php-pear php-pecl-apc mysql
fi

# 2. Конфігурація Apache (VHOST / Alias)
echo "Крок 2: Створення конфігураційного файлу Apache..."
CONF_FILE="$APACHE_CONF_DIR/opensips-cp.conf"

cat <<EOF > "$CONF_FILE"
<Directory /var/www/html/opensips-cp/web>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride None
    Require all granted
</Directory>

<Directory /var/www/html/opensips-cp>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride None
    Require all denied
</Directory>

Alias /cp /var/www/html/opensips-cp/web

<DirectoryMatch "/var/www/html/opensips-cp/web/tools/.*/.*/(template|custom_actions|lib)/">
    Require all denied
</DirectoryMatch>
EOF

# Для Debian потрібно увімкнути конфіг через a2enconf
if [ "$OS_TYPE" == "debian" ]; then
    a2enconf opensips-cp
fi

# 3. Виставлення прав на файли
echo "Крок 3: Налаштування прав доступу для веб-сервера..."
chown -R $WEB_USER:$WEB_USER "$OCP_DIR/"

# 4. Перевірка mysql-клієнта та Імпорт бази даних (Інтерактивно)
echo "----------------------------------------------------------"
# 4. Перевірка БД (Сервер + Клієнт), створення бази та Імпорт схеми OCP
# 4. Повне налаштування бази даних (Сервер + Клієнт + Користувачі + Імпорт)
echo "----------------------------------------------------------"
read -p "Бажаєте налаштувати базу даних та імпортувати схему OCP прямо зараз? (y/n): " IMPORT_DB

if [ "$IMPORT_DB" == "y" ] || [ "$IMPORT_DB" == "Y" ]; then
    
    # 1. ВСТАНОВЛЕННЯ СЕРВЕРА БАЗИ ДАНИХ (MariaDB/MySQL)
    if ! systemctl list-unit-files | grep -qE '(mysql|mariadb)\.service'; then
        echo "Сервер бази даних не знайдено. Починаємо встановлення MariaDB Server..."
        if [ "$OS_TYPE" == "debian" ]; then
            apt-get update
            apt-get install -y mariadb-server default-mysql-client || exit 1
        else
            yum install -y mariadb-server mysql || exit 1
        fi
        echo "Сервер бази даних успішно встановлено."
        systemctl enable mariadb
        systemctl start mariadb
    else
        echo "Перевірка: Сервер бази даних вже встановлено в системі."
        systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null
    fi

    # 2. ПЕРЕВІРКА КЛІЄНТА
    if ! command -v mysql &> /dev/null; then
        if [ "$OS_TYPE" == "debian" ]; then
            apt-get install -y default-mysql-client || exit 1
        else
            yum install -y mysql || exit 1
        fi
    fi

    # 3. НАЛАШТУВАННЯ ІМЕНІ БД ТА ГЕНЕРАЦІЯ ПАРОЛЯ
    read -p "Введіть ім'я бази даних OpenSIPS (дефолт: opensips): " DB_NAME
    DB_NAME=${DB_NAME:-opensips}
    
    # ГЕНЕРУЄМО НАДІЙНИЙ ПАРОЛЬ для користувача 'opensips'
    # Якщо утиліти openssl немає, беремо простіший варіант
    if command -v openssl &> /dev/null; then
        OCP_DB_PASS=$(openssl rand -hex 12)
    else
        OCP_DB_PASS="OpenSipsPass_${RANDOM}"
    fi

    echo "Конфігуруємо MySQL (може знадобитися root-пароль від бази даних)..."
    echo "Якщо ви ставите MariaDB на чисту систему, просто натисніть [Enter], коли запитає пароль."

    # Створюємо базу даних, користувача opensips та видаємо йому повні права
    mysql -u root -p -e "
        CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
        CREATE USER IF NOT EXISTS 'opensips'@'localhost' IDENTIFIED BY '$OCP_DB_PASS';
        ALTER USER 'opensips'@'localhost' IDENTIFIED BY '$OCP_DB_PASS';
        GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'opensips'@'localhost';
        FLUSH PRIVILEGES;
    "

    # 4. ІМПОРТ СХЕМИ ТАБЛИЦЬ OCP
    echo "Імпорт схеми OCP у базу даних..."
    cd "$OCP_DIR" || exit
    if [ -f "config/db_schema.mysql" ]; then
        # Імпортуємо схему вже з під нового користувача opensips та його нового пароля
        mysql -D "$DB_NAME" -u opensips -p"$OCP_DB_PASS" < config/db_schema.mysql
        echo "Схему успішно імпортовано (створено користувача admin з паролем opensips для веб-панелі)."
    else
        echo "Помилка: Файл config/db_schema.mysql не знайдено!"
    fi

    # 5. АВТОМАТИЧНЕ ОНОВЛЕННЯ КОНФІГУРАЦІЙНИХ ФАЙЛІВ OCP
    LOCAL_INC="$OCP_DIR/config/local.inc.php"
    if [ -f "$LOCAL_INC" ]; then
        echo "Оновлюємо параметри підключення у $LOCAL_INC..."
        # Замінюємо localhost на 127.0.0.1 для уникнення помилок сокету (2002)
        sed -i "s|\\\$config->db_host\s*=\s*.*|\$config->db_host = \"127.0.0.1\";|g" "$LOCAL_INC"
        sed -i "s|\\\$config->db_user\s*=\s*.*|\$config->db_user = \"opensips\";|g" "$LOCAL_INC"
        sed -i "s|\\\$config->db_pass\s*=\s*.*|\$config->db_pass = \"$OCP_DB_PASS\";|g" "$LOCAL_INC"
        sed -i "s|\\\$config->db_name\s*=\s*.*|\$config->db_name = \"$DB_NAME\";|g" "$LOCAL_INC"
    fi

    # Оновлюємо паролі в інших можливих файлах конфігурацій інструментів (про всяк випадок)
    echo "Синхронізація паролів в конфігураціях інструментів..."
    find "$OCP_DIR/config/" -type f -exec sed -i "s|opensipsrw|$OCP_DB_PASS|g" {} + 2>/dev/null

    echo "----------------------------------------------------------"
    echo " Створення користувачів та налаштування БД завершено!"
    echo " Створено MySQL користувача: opensips"
    echo " Згенеровано унікальний пароль: $OCP_DB_PASS"
    echo "----------------------------------------------------------"
else
    echo "Пропущено налаштування БД. Не забудьте зробити це вручну."
fi
echo "----------------------------------------------------------"

# 5. Налаштування Cron-завдань для статистики
echo "Крок 4: Налаштування Cron-завдань..."
CRON_TEMPLATE="$OCP_DIR/config/tools/system/smonitor/opensips_stats_cron"

if [ -f "$CRON_TEMPLATE" ]; then
    # Міняємо користувача у файлі cron з root на www-data/apache з міркувань безпеки
    sed -i "s|root|$WEB_USER|g" "$CRON_TEMPLATE"
    
    # Копіюємо в системний каталог cron
    cp "$CRON_TEMPLATE" /etc/cron.d/
    
    # Перезапуск cron сервісу
    if systemctl list-units --type=service | grep -q cron; then
        systemctl restart cron
    else
        systemctl restart crond
    fi
    echo "Cron завдання успішно встановлено."
else
    echo "Попередження: Файл cron-шаблону не знайдено за шляхом $CRON_TEMPLATE"
fi

# 6. Запуск та перезапуск веб-сервера
echo "Крок 5: Запуск сервісів..."
systemctl enable $APACHE_SERVICE
systemctl restart $APACHE_SERVICE

echo "=========================================================="
echo " Встановлення OCP завершено!"
echo " Панель керування доступна за адресою: http://$LOCAL_IP/cp"
echo "=========================================================="
echo "⚠️  Увага! Не забудьте додати модулі httpd та mi_http у ваш opensips.cfg:"
echo "   loadmodule \"httpd.so\""
echo "   modparam(\"httpd\", \"ip\", \"127.0.0.1\")"
echo "   loadmodule \"mi_http.so\""
echo "=========================================================="