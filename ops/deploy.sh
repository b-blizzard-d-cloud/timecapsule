#!/bin/bash
# Выпуск новой версии TimeCapsule на сервере (вариант B).
# Установка на сервере: КОПИЯ в ~/deploy.sh (не ссылка), чтобы git pull не менял исполняемый файл на лету.
set -euo pipefail

APP=/var/www/timecapsule
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
step() { echo "[$(ts)] ==> $*"; }

cd "$APP"

step "Проверка перед выпуском: рабочая копия чистая, конфигурация nginx корректна"
if [ -n "$(git status --porcelain)" ]; then
  echo "Ошибка: на сервере есть локальные изменения, выпуск остановлен:" >&2
  git status --short >&2
  exit 1
fi
sudo nginx -t

step "Забираем новый код из GitHub"
git pull --ff-only

step "Устанавливаем библиотеки"
composer install --no-dev --optimize-autoloader --no-interaction

step "Создаём недостающие таблицы"
php bin/init-db.php

step "Перезагружаем PHP-FPM"
sudo systemctl reload php-fpm

step "Проверка после выпуска: /health"
curl -fsS http://localhost/health
echo

echo "[$(ts)] Готово. На сервере коммит: $(git log -1 --oneline)"
