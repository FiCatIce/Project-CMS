#!/bin/bash
set -e

echo "======================================"
echo " SmartCMS API Starting..."
echo "======================================"

cd /var/www/html

# ---- Wait for MariaDB ----
echo "[*] Waiting for MariaDB..."
MAX_RETRIES=60
RETRY=0
while [ $RETRY -lt $MAX_RETRIES ]; do
    if php -r "try { new PDO('mysql:host=${DB_HOST};port=${DB_PORT}', '${DB_USERNAME}', '${DB_PASSWORD}'); echo 'ok'; } catch(Exception \$e) { exit(1); }" 2>/dev/null; then
        echo "[✓] MariaDB is ready!"
        break
    fi
    RETRY=$((RETRY + 1))
    echo "[*] Attempt $RETRY/$MAX_RETRIES..."
    sleep 2
done

# ---- Generate app key if not set ----
if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "base64:" ]; then
    echo "[*] Generating APP_KEY..."
    php artisan key:generate --force 2>/dev/null || true
fi

# ---- Run migrations ----
echo "[*] Running migrations..."
php artisan migrate --force 2>/dev/null || echo "[!] Migration skipped (may already exist)"

# ---- Cache config ----
echo "[*] Optimizing..."
php artisan config:cache 2>/dev/null || true
php artisan route:cache 2>/dev/null || true
php artisan view:cache 2>/dev/null || true

# ---- Storage link ----
php artisan storage:link 2>/dev/null || true

# ---- Fix permissions ----
chown -R www-data:www-data /var/www/html/storage
chown -R www-data:www-data /var/www/html/bootstrap/cache 2>/dev/null || true

echo "[✓] API Ready!"
exec "$@"
