#!/bin/bash

# Перевірка на запуск від імені root
if [ "$EUID" -ne 0 ]; then
  echo "Будь ласка, запустіть скрипт від імені root (через sudo)."
  exit 1
fi

echo "=========================================================="
echo "         Автоматичне встановлення HOMER 7 (Docker)        "
echo "=========================================================="

# 1. Оновлення системи та встановлення залежностей
echo "Крок 1: Оновлення пакетів та встановлення залежностей..."
apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common git

# 2. Перевірка та встановлення Docker
if ! command -v docker &> /dev/null; then
    echo "Docker не знайдено. Встановлюємо Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo "Docker успішно встановлено."
else
    echo "Перевірка: Docker вже встановлено в системі."
fi

# 3. Перевірка та встановлення Docker Compose
if ! docker compose version &> /dev/null; then
    echo "Docker Compose не знайдено. Встановлюємо..."
    apt-get install -y docker-compose-plugin
else
    echo "Перевірка: Docker Compose вже встановлено."
fi

# Переконаємось, що Docker запущено
systemctl start docker
systemctl enable docker

# 4. Клонування офіційного репозиторію HOMER 7 Docker
HOMER_DIR="/opt/homer7-docker"
if [ -d "$HOMER_DIR" ]; then
    echo "Папка $HOMER_DIR вже існує. Оновлюємо репозиторій..."
    cd "$HOMER_DIR" && git pull
else
    echo "Клонування HOMER 7 Docker репозиторію у $HOMER_DIR..."
    git clone https://github.com/sipcapture/homer7-docker.git "$HOMER_DIR"
fi

# 5. Перехід у конкретний стек Heplify + Prometheus + Grafana
# Використовуємо надійний варіант зі знайденої структури
TARGET_DIR="$HOMER_DIR/heplify-server/hom7-prom-all"

if [ -d "$TARGET_DIR" ]; then
    echo "Переходимо у робочу директорію: $TARGET_DIR"
    cd "$TARGET_DIR" || exit 1
else
    echo "Помилка: Директорію $TARGET_DIR не знайдено! Перевірте структуру репозиторію."
    exit 1
fi

echo "----------------------------------------------------------"
echo "Запуск контейнерів HOMER 7 (Prometheus + Grafana Стек)..."
echo "----------------------------------------------------------"

# Запуск стеку у фоновому режимі
docker compose up -d

echo "Очікуємо запуск PostgreSQL..."

# чекаємо поки DB підніметься
sleep 10

echo "Перевірка ініціалізації бази..."

DB_CONTAINER="db"

# перевіряємо чи є таблиці Homer
TABLE_CHECK=$(docker exec -it $DB_CONTAINER psql -U root -d homer_data -tAc "SELECT to_regclass('public.homer_data');" 2>/dev/null)

if [[ -z "$TABLE_CHECK" || "$TABLE_CHECK" == "null" ]]; then
    echo "База не ініціалізована. Виконуємо ініціалізацію..."

    # шукаємо SQL файли в контейнері webapp
    INIT_SQL=$(docker exec homer-webapp find / -name "*.sql" 2>/dev/null | head -n 1)

    if [ ! -z "$INIT_SQL" ]; then
        echo "Знайдено SQL: $INIT_SQL"
        docker exec -i $DB_CONTAINER psql -U root -d homer_data < <(docker exec homer-webapp cat $INIT_SQL)
        echo "Ініціалізація завершена"
    else
        echo "⚠️ SQL schema не знайдено. Можливо потрібно оновити образ Homer."
    fi
else
    echo "База вже ініціалізована"
fi

echo "=========================================================="
echo "         Встановлення HOMER 7 успішно завершено!          "
echo "=========================================================="
echo " Веб-панель Grafana доступна за адресою вашого сервера."
echo " Спробуйте відкрити в браузері IP вашого сервера (порт за дефолтом)."
echo " Порти для збору трафіку:"
echo "   - 9060 UDP/TCP (HEP протокол для OpenSIPS/FreeSWITCH)"
echo "=========================================================="