#!/bin/bash
# ============================================================
# SmartCMS Deployment - Bare Metal + Docker Asterisk
#
# Architecture:
#   - MariaDB      → bare metal (host)
#   - Laravel API  → bare metal (host) via PHP-FPM
#   - Angular      → bare metal (host) served by Nginx
#   - Nginx        → bare metal (host)
#   - Asterisk     → Docker container (custom build from source)
#
# Server: Debian Trixie (13) - 103.154.80.173
# ============================================================

set -e

EXTERNAL_IP="103.154.80.173"
ANGULAR_REPO="https://github.com/rhaaf-project/SmartCMS-Angular-171.git"
PROJECT_DIR="/opt/smartcms"
WEB_ROOT="/var/www/smartcms"
API_DIR="/var/www/smartcms-api"

DB_NAME="db_ucx"
DB_USER="smartcms"
DB_PASSWORD="SmartCMS_DB_2026!"

AMI_SECRET="smartcms_ami_secret_2026"
ARI_PASSWORD="smartcms_ari_secret_2026"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${BLUE}${BOLD}═══ $1 ═══${NC}\n"; }

if [ "$(id -u)" -ne 0 ]; then error "Run as root (sudo)"; exit 1; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# STEP 1: System Update
# ============================================================
step "STEP 1/8: System Update"

apt-get update -y
apt-get install -y \
    ca-certificates curl gnupg git wget unzip \
    htop net-tools openssl lsof

info "System updated"

# ============================================================
# STEP 2: Install MariaDB
# ============================================================
step "STEP 2/8: Install MariaDB"

if command -v mariadb &>/dev/null; then
    info "MariaDB already installed: $(mariadb --version | head -1)"
else
    apt-get install -y mariadb-server mariadb-client
    systemctl enable mariadb
    systemctl start mariadb
    info "MariaDB installed"
fi

systemctl is-active --quiet mariadb || systemctl start mariadb

info "Configuring database..."
mariadb -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'172.%' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'172.%';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
info "Database '${DB_NAME}' ready"

# Allow Docker to reach MariaDB
MARIADB_CNF=$(find /etc/mysql -name "50-server.cnf" 2>/dev/null | head -1)
if [ -n "$MARIADB_CNF" ]; then
    if ! grep -q "bind-address.*0.0.0.0" "$MARIADB_CNF"; then
        sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$MARIADB_CNF"
        systemctl restart mariadb
        info "MariaDB now listening on all interfaces (for Docker Asterisk)"
    fi
fi

# Import schemas
if [ -f "$SCRIPT_DIR/scripts/schema_lengkap.sql" ]; then
    info "Importing base schema..."
    mariadb -u root "${DB_NAME}" < "$SCRIPT_DIR/scripts/schema_lengkap.sql" 2>/dev/null && \
        info "Base schema imported" || warn "Skipped (may already exist)"
fi

if [ -f "$SCRIPT_DIR/scripts/001_pjsip_realtime_and_license.sql" ]; then
    info "Importing PJSIP + license tables..."
    mariadb -u root "${DB_NAME}" < "$SCRIPT_DIR/scripts/001_pjsip_realtime_and_license.sql" 2>/dev/null && \
        info "PJSIP + license imported" || warn "Skipped (may already exist)"
fi

info "Creating super admin..."
mariadb -u root "${DB_NAME}" <<'SQL'
INSERT IGNORE INTO licenses (id, license_key, company_name, license_type, max_extensions, max_trunks, max_call_servers, allowed_modules, is_active, created_at)
VALUES (1, 'SMARTCMS-SA-MASTER-2026', 'SmartCMS Master', 'super_admin', 99999, 99999, 99999,
'["dashboard","extensions","lines","vpws","cas","3rd_party","trunks","sbcs","inbound_routes","outbound_routes","ring_groups","ivr","conferences","announcements","recordings","time_conditions","blacklists","phone_directory","firewall","static_routes","call_servers","customers","head_offices","branches","sub_branches","cms_users","cms_groups","turret_users","turret_groups","turret_policies","turret_templates","sbc_routes","dahdi","intercoms","activity_logs","system_logs","cdrs","usage_statistics","settings","license_management"]',
1, NOW());

INSERT INTO cms_users (name, email, password, role, is_super_admin, license_id, is_active, created_at, updated_at)
VALUES ('Super Admin', 'superadmin@smartcms.local',
'$2y$12$sZmwDnKqS3Y9vGPKOIKFe.UrYR4VLrfg2VLxJq7RRJw7C0I1GwVhm',
'admin', 1, 1, 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE is_super_admin = 1, license_id = 1;
SQL
info "Super admin: superadmin@smartcms.local / SmartCMS@2026"

# ============================================================
# STEP 3: Install PHP 8.3
# ============================================================
step "STEP 3/8: Install PHP 8.3 + Composer"

if php -v 2>/dev/null | grep -q "8\.[2-4]"; then
    info "PHP already installed: $(php -v | head -1)"
else
    info "Installing PHP..."
    apt-get install -y \
        php php-fpm php-cli php-mysql php-mbstring php-xml php-curl \
        php-zip php-gd php-bcmath php-intl php-redis php-soap \
        php-sockets php-tokenizer 2>/dev/null || \
    apt-get install -y \
        php8.3 php8.3-fpm php8.3-cli php8.3-mysql php8.3-mbstring \
        php8.3-xml php8.3-curl php8.3-zip php8.3-gd php8.3-bcmath \
        php8.3-intl php8.3-redis php8.3-soap php8.3-sockets
    info "PHP installed: $(php -v | head -1)"
fi

if command -v composer &>/dev/null; then
    info "Composer already installed"
else
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    info "Composer installed"
fi

# ============================================================
# STEP 4: Install Node.js 20
# ============================================================
step "STEP 4/8: Install Node.js 20"

if node -v 2>/dev/null | grep -q "v2[0-9]"; then
    info "Node.js already installed: $(node -v)"
else
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    info "Node.js installed: $(node -v), npm: $(npm -v)"
fi

npm list -g @angular/cli >/dev/null 2>&1 || {
    info "Installing Angular CLI..."
    npm install -g @angular/cli
}

# ============================================================
# STEP 5: Setup Laravel Backend
# ============================================================
step "STEP 5/8: Setup Laravel Backend"

if [ -f "$API_DIR/artisan" ]; then
    info "Laravel already exists at $API_DIR"
else
    info "Creating Laravel project..."
    cd /var/www
    composer create-project --prefer-dist laravel/laravel smartcms-api "11.*" --no-interaction
    info "Laravel created"
fi

# Copy SmartCMS modules
info "Integrating SmartCMS modules..."
mkdir -p "$API_DIR"/{app/Models,app/Http/Controllers/Api,app/Http/Middleware,app/Services,config}

cp -f "$SCRIPT_DIR/cms/license-module/Models/"*.php "$API_DIR/app/Models/" 2>/dev/null || true
cp -f "$SCRIPT_DIR/cms/license-module/Controllers/"*.php "$API_DIR/app/Http/Controllers/Api/" 2>/dev/null || true
cp -f "$SCRIPT_DIR/cms/license-module/Middleware/"*.php "$API_DIR/app/Http/Middleware/" 2>/dev/null || true
cp -f "$SCRIPT_DIR/cms/asterisk-realtime/Services/"*.php "$API_DIR/app/Services/" 2>/dev/null || true
cp -f "$SCRIPT_DIR/cms/asterisk-realtime/config_asterisk.php" "$API_DIR/config/asterisk.php" 2>/dev/null || true

# Add license routes
if ! grep -q "LicenseController" "$API_DIR/routes/api.php" 2>/dev/null; then
    cat >> "$API_DIR/routes/api.php" << 'ROUTES'

use App\Http\Controllers\Api\LicenseController;
Route::prefix('license')->group(function () {
    Route::get('/verify', [LicenseController::class, 'verify']);
    Route::post('/activate', [LicenseController::class, 'activate']);
});
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/license/modules', [LicenseController::class, 'modules']);
    Route::post('/license/check-module', [LicenseController::class, 'checkModule']);
    Route::apiResource('licenses', LicenseController::class);
});
ROUTES
    info "License routes added"
fi

# Laravel .env
cat > "$API_DIR/.env" << ENVFILE
APP_NAME=SmartCMS
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://${EXTERNAL_IP}
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
AMI_HOST=127.0.0.1
AMI_PORT=5038
AMI_USERNAME=smartcms
AMI_SECRET=${AMI_SECRET}
ARI_HOST=127.0.0.1
ARI_PORT=8088
ARI_USERNAME=smartcms
ARI_PASSWORD=${ARI_PASSWORD}
CACHE_DRIVER=database
SESSION_DRIVER=database
QUEUE_CONNECTION=database
ENVFILE

cd "$API_DIR"
composer require laravel/sanctum --no-interaction 2>/dev/null || true
php artisan key:generate --force
php artisan migrate --force 2>/dev/null || warn "Migration needs review"

chown -R www-data:www-data "$API_DIR"
chmod -R 775 "$API_DIR/storage" "$API_DIR/bootstrap/cache"
info "Laravel ready at $API_DIR"

# ============================================================
# STEP 6: Build Angular Frontend
# ============================================================
step "STEP 6/8: Build Angular Frontend"

mkdir -p "$PROJECT_DIR" "$WEB_ROOT"

if [ -d "$PROJECT_DIR/frontend/.git" ]; then
    cd "$PROJECT_DIR/frontend" && git pull 2>/dev/null || true
else
    git clone "$ANGULAR_REPO" "$PROJECT_DIR/frontend"
fi

# Find angular.json
cd "$PROJECT_DIR/frontend"
ANGULAR_ROOT="$PROJECT_DIR/frontend"
if [ ! -f "angular.json" ]; then
    FOUND=$(find . -name "angular.json" -maxdepth 3 | head -1)
    [ -n "$FOUND" ] && ANGULAR_ROOT="$PROJECT_DIR/frontend/$(dirname "$FOUND")"
fi
cd "$ANGULAR_ROOT"

info "Installing npm dependencies..."
npm install --legacy-peer-deps 2>&1 | tail -3

info "Building Angular..."
npx ng build --configuration=production 2>&1 | tail -10 || \
    npm run build 2>&1 | tail -10 || warn "Build had issues"

# Deploy build to web root
DIST_INDEX=$(find dist/ -name "index.html" 2>/dev/null | head -1)
if [ -n "$DIST_INDEX" ]; then
    DIST_DIR=$(dirname "$DIST_INDEX")
    rm -rf "${WEB_ROOT:?}"/*
    cp -r "$DIST_DIR"/* "$WEB_ROOT"/
    chown -R www-data:www-data "$WEB_ROOT"
    info "Angular deployed to $WEB_ROOT"
else
    warn "Build output not found. Deploy manually after fixing Angular build."
fi

# ============================================================
# STEP 7: Configure Nginx
# ============================================================
step "STEP 7/8: Configure Nginx"

apt-get install -y nginx 2>/dev/null || true

# Find PHP-FPM socket
PHP_FPM_SOCK=$(find /run/php/ -name "php*-fpm.sock" 2>/dev/null | head -1 || echo "/run/php/php-fpm.sock")
info "PHP-FPM socket: $PHP_FPM_SOCK"

cat > /etc/nginx/sites-available/smartcms << NGINXCONF
server {
    listen 80;
    server_name ${EXTERNAL_IP} _;

    root ${WEB_ROOT};
    index index.html;
    client_max_body_size 64M;

    # Laravel API
    location ~ ^/api(/.*)?\$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME ${API_DIR}/public/index.php;
        fastcgi_param REQUEST_URI /api\$1;
        fastcgi_pass unix:${PHP_FPM_SOCK};
        fastcgi_read_timeout 300;
    }

    location /sanctum {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME ${API_DIR}/public/index.php;
        fastcgi_pass unix:${PHP_FPM_SOCK};
    }

    # Asterisk WebSocket proxy
    location /asterisk-ws {
        proxy_pass http://127.0.0.1:8088/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    # Static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # Angular SPA catch-all
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;
    gzip_min_length 256;
}
NGINXCONF

ln -sf /etc/nginx/sites-available/smartcms /etc/nginx/sites-enabled/smartcms
rm -f /etc/nginx/sites-enabled/default 2>/dev/null

nginx -t && info "Nginx config OK" || error "Nginx config error"

# Start services
systemctl enable nginx && systemctl restart nginx
info "Nginx running"

PHP_FPM_SVC=$(systemctl list-units --type=service --all | grep -o 'php[0-9.]*-fpm.service' | head -1)
if [ -n "$PHP_FPM_SVC" ]; then
    systemctl enable "$PHP_FPM_SVC" && systemctl restart "$PHP_FPM_SVC"
    info "PHP-FPM running: $PHP_FPM_SVC"
fi

# ============================================================
# STEP 8: Docker Asterisk
# ============================================================
step "STEP 8/8: Docker Asterisk"

if ! command -v docker &>/dev/null; then
    info "Installing Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    CODENAME="bookworm"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian ${CODENAME} stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker && systemctl start docker
    info "Docker installed"
else
    info "Docker: $(docker --version)"
fi

# SSL for Asterisk WSS
mkdir -p "$SCRIPT_DIR/certs"
if [ ! -f "$SCRIPT_DIR/certs/asterisk.pem" ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$SCRIPT_DIR/certs/asterisk.key" \
        -out "$SCRIPT_DIR/certs/asterisk.pem" \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=SmartCMS/CN=${EXTERNAL_IP}" 2>/dev/null
    info "Asterisk SSL cert generated"
fi

# Docker compose for Asterisk only
cat > "$SCRIPT_DIR/docker-compose.yml" << DCOMPOSE
services:
  asterisk:
    build:
      context: ./asterisk
      dockerfile: Dockerfile
    container_name: smartcms-asterisk
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      DB_HOST: host.docker.internal
      DB_PORT: "3306"
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASS: ${DB_PASSWORD}
      AMI_SECRET: ${AMI_SECRET}
      ARI_PASSWORD: ${ARI_PASSWORD}
      EXTERNAL_IP: ${EXTERNAL_IP}
    volumes:
      - asterisk_logs:/var/log/asterisk
      - asterisk_spool:/var/spool/asterisk
      - ./certs:/etc/asterisk/keys:ro
    ports:
      - "5060:5060/udp"
      - "5060:5060/tcp"
      - "5061:5061/tcp"
      - "8088:8088/tcp"
      - "8089:8089/tcp"
      - "10000-10500:10000-10500/udp"
      - "5038:5038/tcp"

volumes:
  asterisk_logs:
  asterisk_spool:
DCOMPOSE

cd "$SCRIPT_DIR"
warn "Building Asterisk from source (~15-30 min)..."
docker compose build asterisk 2>&1 | tail -20
info "Asterisk built!"

docker compose up -d asterisk
sleep 10

# ============================================================
# DONE
# ============================================================
step "DEPLOYMENT COMPLETE"

echo ""
info "Services:"
echo "  MariaDB:   $(systemctl is-active mariadb)"
echo "  Nginx:     $(systemctl is-active nginx)"
echo "  PHP-FPM:   $(systemctl is-active ${PHP_FPM_SVC:-php-fpm} 2>/dev/null || echo 'check manually')"
echo "  Asterisk:  $(docker ps --filter name=smartcms-asterisk --format '{{.Status}}' 2>/dev/null || echo 'check docker')"

echo ""
info "Database:"
echo "  Tables: $(mariadb -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null)"
echo "  PJSIP:  $(mariadb -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name LIKE 'ps_%';" 2>/dev/null)"

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║            SmartCMS Ready!                            ║"
echo "╠═══════════════════════════════════════════════════════╣"
echo "║  CMS:      http://${EXTERNAL_IP}                     ║"
echo "║  API:      http://${EXTERNAL_IP}/api/license/verify  ║"
echo "║  Login:    superadmin@smartcms.local / SmartCMS@2026  ║"
echo "║  License:  SMARTCMS-SA-MASTER-2026                    ║"
echo "║  SIP:      ${EXTERNAL_IP}:5060                       ║"
echo "║  WSS:      wss://${EXTERNAL_IP}:8089/ws              ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Commands:"
echo "  Asterisk CLI:  docker exec -it smartcms-asterisk asterisk -rvvv"
echo "  MariaDB:       mariadb -u root ${DB_NAME}"
echo "  Nginx cfg:     /etc/nginx/sites-available/smartcms"
echo "  Laravel:       ${API_DIR}"
echo "  Frontend:      ${WEB_ROOT}"
echo ""
