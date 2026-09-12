#!/bin/bash
# Восстановление конфигов Fornex VPS (Redis + tinyproxy) — 12.09.2026.
#
# Запускается ПРЯМО на Fornex VPS (или новой VPS взамен неё). В отличие
# от config.php на Джино (см. scripts/restore_landing_config.py — там
# прямой доступ к БД, тот же сервер), здесь платформа физически на
# другой машине — единственный путь получить секрет автоматически это
# HTTP-запрос к самой платформе через новый admin-only эндпоинт
# GET /api/v1/admin/backups/secrets-restore (см. app/routers/
# backups_router.py, осознанное исключение из правила "секрет никогда
# не в открытом виде через API", принято пользователем 12.09.2026).
#
# Специально не тянет ничего кроме curl+python3 — оба уже есть на
# любой чистой Ubuntu VPS, никаких доп. зависимостей на этот сервер
# ставить не нужно (тот же принцип "VPS не часть бизнес-логики",
# см. RUNBOOK-INFRASTRUKTURA.md).
#
# Требует, чтобы платформа (platform.kapfond.ru) уже была на ходу к
# этому моменту, и чтобы секреты redis.conf/tinyproxy.conf были заранее
# один раз сохранены в коннекторе «Секреты серверов (восстановление)»
# через интерфейс платформы.
#
# Запуск:
#   bash restore_fornex_secrets.sh

set -e

PLATFORM_URL="https://platform.kapfond.ru"

read -rp "Логин на платформе (телефон/email администратора): " LOGIN
read -rsp "Пароль: " PASSWORD
echo

TOKEN=$(curl -s -X POST "$PLATFORM_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"login\":\"$LOGIN\",\"password\":\"$PASSWORD\"}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token',''))")

if [ -z "$TOKEN" ]; then
  echo "ОШИБКА: не удалось войти — проверьте логин/пароль и то, что у пользователя is_admin=True"
  exit 1
fi

fetch_secret() {
  local field="$1"
  local outfile="$2"
  local value
  value=$(curl -s -G "$PLATFORM_URL/api/v1/admin/backups/secrets-restore" \
    --data-urlencode "field=$field" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('value', 'ОШИБКА: ' + str(d.get('detail','пусто'))), end='')")
  if [[ "$value" == ОШИБКА* ]] || [ -z "$value" ]; then
    echo "Не удалось получить «$field»: $value"
    return 1
  fi
  echo "$value" > "$outfile"
  echo "Записан: $outfile"
}

fetch_secret "redis.conf (Fornex)" /etc/redis/redis.conf
fetch_secret "tinyproxy.conf (Fornex)" /etc/tinyproxy/tinyproxy.conf

systemctl restart redis-server tinyproxy
echo "Сервисы redis-server и tinyproxy перезапущены."
echo "Проверка: redis-cli -a <пароль_из_конфига> ping — ожидается PONG"
