#!/bin/bash
# ============================================================
# SmartCMS Native Deploy - Debian Trixie (103.154.80.173)
# Semua install langsung di server, TANPA Docker
#
# Stack:
#   - MariaDB 11.x (dari Debian repo)
#   - PHP 8.3 + Laravel (dari sury.org)
#   - Node 20 + Angular 17 (build static)
#   - Nginx (reverse proxy + serve Angular)
#   - Asterisk 21 (compile from source)
#
# Usage: sudo ./deploy-native.sh
# ============================================================

set -e

EXTERNAL_IP="103.154.80.173"
DB_NAME="db_ucx"
DB_USER="smartcms"
DB_PASSWORD="SmartCMS_DB_2026!"
DB_ROOT_PASSWORD="SmartCMS_Root_2026!"
AMI_SECRET="smartcms_ami_secret_2026"
ARI_PASSWORD="smartcms_ari_secret_2026"
ANGULAR_REPO="https://github.com/rhaaf-project/SmartCMS-Angular-171.git"
PROJECT_DIR="/opt/smartcms"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${BLUE}${BOLD}═══ $1 ═══${NC}\n"; }

[ "$(id -u)" -ne 0 ] && { error "Run as root: sudo ./deploy-native.sh"; exit 1; }

# ============================================================
# STEP 1: System + Base Packages
# ============================================================
step "STEP 1/8: System Update"

apt-get update -y
apt-get upgrade -y
apt-get install -y \
    curl wget git unzip htop net-tools lsof \
    ca-certificates gnupg openssl \
    build-essential pkg-config autoconf automake libtool

info "System updated"

# ============================================================
# STEP 2: MariaDB
# ============================================================
step "STEP 2/8: MariaDB"

if command -v mariadb &>/dev/null; then
    info "MariaDB already installed: $(mariadb --version | head -1)"
else
    apt-get install -y mariadb-server mariadb-client
    systemctl enable mariadb
    systemctl start mariadb
    info "MariaDB installed"
fi

# Secure + create DB
info "Configuring database..."
mariadb -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
info "Database '${DB_NAME}' ready, user '${DB_USER}' created"

# Import schemas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/schema_lengkap.sql" ]; then
    info "Importing base schema..."
    mariadb -u root "${DB_NAME}" < "$SCRIPT_DIR/scripts/schema_lengkap.sql" 2>/dev/null && \
        info "Base schema imported" || warn "Base schema skipped (may already exist)"
fi

if [ -f "$SCRIPT_DIR/scripts/001_pjsip_realtime_and_license.sql" ]; then
    info "Importing PJSIP realtime + license tables..."
    mariadb -u root "${DB_NAME}" < "$SCRIPT_DIR/scripts/001_pjsip_realtime_and_license.sql" 2>/dev/null && \
        info "PJSIP + License tables imported" || warn "PJSIP tables skipped (may already exist)"
fi

# Create super admin
info "Creating super admin user..."
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
info "Super admin created"

# ============================================================
# STEP 3: PHP 8.3 + Composer
# ============================================================
step "STEP 3/8: PHP 8.3"

if php -v 2>/dev/null | grep -q "8.3"; then
    info "PHP 8.3 already installed"
else
    # sury.org repo (already in your sources)
    if [ ! -f /etc/apt/sources.list.d/sury-php.list ] && [ ! -f /etc/apt/sources.list.d/php.list ]; then
        curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
        dpkg -i /tmp/debsuryorg-archive-keyring.deb
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
            > /etc/apt/sources.list.d/sury-php.list
        apt-get update
    fi

    apt-get install -y \
        php8.3-fpm php8.3-cli php8.3-common \
        php8.3-mysql php8.3-mbstring php8.3-xml php8.3-curl \
        php8.3-zip php8.3-gd php8.3-bcmath php8.3-intl \
        php8.3-readline php8.3-opcache php8.3-redis php8.3-sockets
    info "PHP 8.3 installed"
fi

# Composer
if command -v composer &>/dev/null; then
    info "Composer already installed"
else
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    info "Composer installed"
fi

# Configure PHP-FPM
PHP_FPM_CONF="/etc/php/8.3/fpm/pool.d/www.conf"
if [ -f "$PHP_FPM_CONF" ]; then
    sed -i 's/^user = .*/user = www-data/' "$PHP_FPM_CONF"
    sed -i 's/^group = .*/group = www-data/' "$PHP_FPM_CONF"
    sed -i 's|^listen = .*|listen = /run/php/php8.3-fpm.sock|' "$PHP_FPM_CONF"
fi

systemctl enable php8.3-fpm
systemctl restart php8.3-fpm
info "PHP-FPM configured"

# ============================================================
# STEP 4: Node.js 20 + Angular CLI
# ============================================================
step "STEP 4/8: Node.js 20"

if node -v 2>/dev/null | grep -q "v20"; then
    info "Node.js 20 already installed"
else
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    info "Node.js installed: $(node -v)"
fi

npm install -g @angular/cli@17 2>/dev/null || true
info "Angular CLI: $(ng version 2>/dev/null | grep 'Angular CLI' || echo 'installed')"

# ============================================================
# STEP 5: Clone & Build Angular Frontend
# ============================================================
step "STEP 5/8: Angular Frontend"

mkdir -p "$PROJECT_DIR"

if [ -d "$PROJECT_DIR/frontend/.git" ]; then
    info "Frontend exists, pulling latest..."
    cd "$PROJECT_DIR/frontend" && git pull 2>/dev/null || true
else
    info "Cloning Angular frontend..."
    rm -rf "$PROJECT_DIR/frontend"
    git clone "$ANGULAR_REPO" "$PROJECT_DIR/frontend"
fi

cd "$PROJECT_DIR/frontend"

# Find angular.json (might be in subdirectory)
ANGULAR_ROOT=$(find . -name "angular.json" -maxdepth 3 | head -1 | xargs dirname 2>/dev/null)
if [ -n "$ANGULAR_ROOT" ] && [ "$ANGULAR_ROOT" != "." ]; then
    info "Angular project found in: $ANGULAR_ROOT"
    cd "$ANGULAR_ROOT"
fi

info "Installing npm dependencies..."
npm ci --legacy-peer-deps 2>/dev/null || npm install --legacy-peer-deps

info "Building Angular for production..."
npx ng build --configuration=production 2>/dev/null || npm run build -- --configuration=production 2>/dev/null || npm run build 2>/dev/null

# Find the build output
DIST_DIR=""
for candidate in dist/*/browser dist/browser dist/*; do
    if [ -f "$candidate/index.html" ] 2>/dev/null; then
        DIST_DIR="$(pwd)/$candidate"
        break
    fi
done

if [ -d "dist" ] && [ -z "$DIST_DIR" ]; then
    DIST_DIR="$(pwd)/dist"
fi

if [ -n "$DIST_DIR" ]; then
    info "Angular build output: $DIST_DIR"
    # Symlink for nginx
    rm -rf /var/www/smartcms
    ln -sf "$DIST_DIR" /var/www/smartcms
    info "Linked to /var/www/smartcms"
else
    warn "Angular build output not found — creating placeholder"
    mkdir -p /var/www/smartcms
    echo '<!DOCTYPE html><html><head><title>SmartCMS</title></head><body><h1>SmartCMS - Build Pending</h1><p><a href="/api">API</a></p></body></html>' > /var/www/smartcms/index.html
fi

# ============================================================
# STEP 6: Laravel Backend
# ============================================================
step "STEP 6/8: Laravel Backend"

if [ -f "$PROJECT_DIR/backend/artisan" ]; then
    info "Laravel backend already exists"
else
    info "Creating Laravel project..."
    mkdir -p "$PROJECT_DIR/backend"
    cd "$PROJECT_DIR"
    composer create-project --prefer-dist laravel/laravel backend "11.*" --no-interaction 2>&1 | tail -5

    cd "$PROJECT_DIR/backend"
    composer require laravel/sanctum --no-interaction 2>&1 | tail -3
    info "Laravel project created with Sanctum"
fi

cd "$PROJECT_DIR/backend"

# Integrate SmartCMS modules
info "Integrating SmartCMS modules..."
mkdir -p app/Models app/Http/Controllers/Api app/Http/Middleware app/Services config

# Copy modules from deploy package
for f in "$SCRIPT_DIR/cms/license-module/Models/"*.php; do
    [ -f "$f" ] && cp -f "$f" app/Models/
done
for f in "$SCRIPT_DIR/cms/license-module/Controllers/"*.php; do
    [ -f "$f" ] && cp -f "$f" app/Http/Controllers/Api/
done
for f in "$SCRIPT_DIR/cms/license-module/Middleware/"*.php; do
    [ -f "$f" ] && cp -f "$f" app/Http/Middleware/
done
for f in "$SCRIPT_DIR/cms/asterisk-realtime/Services/"*.php; do
    [ -f "$f" ] && cp -f "$f" app/Services/
done
[ -f "$SCRIPT_DIR/cms/asterisk-realtime/config_asterisk.php" ] && \
    cp -f "$SCRIPT_DIR/cms/asterisk-realtime/config_asterisk.php" config/asterisk.php

# Add license routes
if ! grep -q "LicenseController" routes/api.php 2>/dev/null; then
    cat >> routes/api.php << 'ROUTES'

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

# Configure .env
cat > .env << ENVFILE
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

SANCTUM_STATEFUL_DOMAINS=${EXTERNAL_IP}
SESSION_DOMAIN=${EXTERNAL_IP}
ENVFILE

# Generate key + migrate
php artisan key:generate --force
php artisan migrate --force 2>/dev/null || warn "Migration had warnings (tables may exist)"
php artisan config:cache 2>/dev/null || true
php artisan route:cache 2>/dev/null || true
php artisan storage:link 2>/dev/null || true

# Permissions
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

info "Laravel configured"

# ============================================================
# STEP 7: Nginx Configuration
# ============================================================
step "STEP 7/8: Nginx"

if ! command -v nginx &>/dev/null; then
    apt-get install -y nginx
fi

cat > /etc/nginx/sites-available/smartcms << 'NGINXCONF'
server {
    listen 80;
    server_name 103.154.80.173 _;

    client_max_body_size 64M;

    # ---- Angular Frontend ----
    root /var/www/smartcms;
    index index.html;

    # ---- Laravel API ----
    location /api {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
        proxy_buffering off;
    }

    location /sanctum {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /broadcasting {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    # ---- Asterisk WebSocket proxy ----
    location /ws {
        proxy_pass http://127.0.0.1:8088/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    # ---- Static assets ----
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # ---- Angular SPA fallback ----
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript image/svg+xml;
    gzip_min_length 256;
}
NGINXCONF

# Enable site
ln -sf /etc/nginx/sites-available/smartcms /etc/nginx/sites-enabled/smartcms
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl enable nginx && systemctl restart nginx
info "Nginx configured and running"

# ============================================================
# STEP 8: Asterisk 21 (Compile from Source)
# ============================================================
step "STEP 8/8: Asterisk 21 (Compile from Source)"

ASTERISK_VERSION="21.7.0"

if asterisk -V 2>/dev/null | grep -q "21"; then
    info "Asterisk 21 already installed: $(asterisk -V)"
else
    info "Installing Asterisk build dependencies..."
    apt-get install -y --no-install-recommends \
        libedit-dev libjansson-dev libxml2-dev libsqlite3-dev \
        libssl-dev libncurses5-dev uuid-dev libsrtp2-dev \
        libspandsp-dev libcurl4-openssl-dev libnewt-dev \
        libpopt-dev libical-dev libiksemel-dev libsnmp-dev \
        libunbound-dev libspeex-dev libspeexdsp-dev \
        libresample1-dev libopus-dev liburiparser-dev \
        unixodbc unixodbc-dev odbc-mariadb libmariadb-dev \
        sox subversion python3 python3-dev file

    cd /usr/src
    info "Downloading Asterisk ${ASTERISK_VERSION}..."
    wget -q "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz"
    tar xzf "asterisk-${ASTERISK_VERSION}.tar.gz"
    rm "asterisk-${ASTERISK_VERSION}.tar.gz"

    cd "asterisk-${ASTERISK_VERSION}"

    info "Running install_prereq..."
    yes | contrib/scripts/install_prereq install 2>&1 | tail -5

    info "Configuring (with bundled pjproject)..."
    ./configure \
        --with-pjproject-bundled \
        --with-jansson-bundled \
        --with-crypto --with-ssl --with-srtp \
        --with-unixodbc --with-opus \
        --with-resample --with-speex --with-speexdsp \
        --with-libedit \
        --libdir=/usr/lib/x86_64-linux-gnu 2>&1 | tail -10

    info "Selecting modules..."
    make menuselect.makeopts
    menuselect/menuselect \
        --enable res_pjsip \
        --enable res_pjsip_transport_websocket \
        --enable res_http_websocket \
        --enable res_odbc \
        --enable res_config_odbc \
        --enable cdr_odbc \
        --enable func_odbc \
        --enable res_ari \
        --enable res_ari_channels \
        --enable res_ari_bridges \
        --enable res_ari_endpoints \
        --enable res_ari_events \
        --enable res_stasis \
        --enable app_mixmonitor \
        --enable codec_opus \
        --enable CORE-SOUNDS-EN-ULAW \
        --enable CORE-SOUNDS-EN-ALAW \
        --enable MOH-OPSOUND-ULAW \
        menuselect.makeopts 2>&1 | tail -5

    info "Compiling (this takes ~15-20 minutes)..."
    make -j$(nproc) 2>&1 | tail -5
    make install 2>&1 | tail -3
    make samples 2>&1 | tail -3
    make config 2>&1 | tail -3
    make install-logrotate 2>&1 | tail -3
    ldconfig

    # Create asterisk user
    groupadd -r asterisk 2>/dev/null || true
    useradd -r -g asterisk -d /var/lib/asterisk -s /bin/false asterisk 2>/dev/null || true

    chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk \
        /var/log/asterisk /var/spool/asterisk /var/run/asterisk 2>/dev/null || true

    info "Asterisk $(asterisk -V) installed!"
fi

# ---- Configure ODBC ----
info "Configuring ODBC for Asterisk→MariaDB..."

DRIVER_PATH=$(find /usr/lib -name "libmaodbc.so" 2>/dev/null | head -1)
[ -z "$DRIVER_PATH" ] && DRIVER_PATH=$(find /usr/lib -name "libmyodbc*.so" 2>/dev/null | head -1)

cat > /etc/odbcinst.ini << EOF
[MariaDB]
Description = MariaDB ODBC Connector
Driver = ${DRIVER_PATH}
Setup = ${DRIVER_PATH}
UsageCount = 1
Threading = 2
EOF

cat > /etc/odbc.ini << EOF
[asterisk-connector]
Description = Asterisk MariaDB Connection
Driver = MariaDB
Server = 127.0.0.1
Port = 3306
Database = ${DB_NAME}
User = ${DB_USER}
Password = ${DB_PASSWORD}
Option = 3
Charset = utf8mb4
EOF

info "ODBC configured"

# ---- Copy Asterisk configs ----
info "Applying SmartCMS Asterisk configs..."
CONF_SRC="$SCRIPT_DIR/asterisk/configs"
if [ -d "$CONF_SRC" ]; then
    for conf in pjsip.conf sorcery.conf extconfig.conf res_odbc.conf \
                extensions.conf manager.conf http.conf ari.conf \
                modules.conf rtp.conf cdr_odbc.conf asterisk.conf; do
        [ -f "$CONF_SRC/$conf" ] && cp -f "$CONF_SRC/$conf" /etc/asterisk/
    done
    info "Asterisk configs applied"
fi

# Fix external IP in pjsip.conf
sed -i "s/external_media_address=.*/external_media_address=${EXTERNAL_IP}/" /etc/asterisk/pjsip.conf
sed -i "s/external_signaling_address=.*/external_signaling_address=${EXTERNAL_IP}/" /etc/asterisk/pjsip.conf

# Fix ODBC credentials in res_odbc.conf
sed -i "s|\${DB_USER}|${DB_USER}|g" /etc/asterisk/res_odbc.conf
sed -i "s|\${DB_PASS}|${DB_PASSWORD}|g" /etc/asterisk/res_odbc.conf

# Generate self-signed cert for WSS
mkdir -p /etc/asterisk/keys
if [ ! -f /etc/asterisk/keys/asterisk.pem ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/asterisk/keys/asterisk.key \
        -out /etc/asterisk/keys/asterisk.pem \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=SmartCMS/CN=${EXTERNAL_IP}" 2>/dev/null
    chown -R asterisk:asterisk /etc/asterisk/keys
    info "Asterisk SSL cert generated"
fi

chown -R asterisk:asterisk /etc/asterisk

# Set Asterisk to run as asterisk user
sed -i 's/^#AST_USER=.*/AST_USER="asterisk"/' /etc/default/asterisk 2>/dev/null || true
sed -i 's/^#AST_GROUP=.*/AST_GROUP="asterisk"/' /etc/default/asterisk 2>/dev/null || true

systemctl enable asterisk 2>/dev/null || true
systemctl restart asterisk 2>/dev/null || asterisk -g 2>/dev/null

info "Asterisk started"

# ============================================================
# Start Laravel dev server (or setup supervisor/systemd)
# ============================================================
step "Starting Laravel API"

# Create systemd service for Laravel
cat > /etc/systemd/system/smartcms-api.service << SVCFILE
[Unit]
Description=SmartCMS Laravel API
After=network.target mariadb.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=${PROJECT_DIR}/backend
ExecStart=/usr/bin/php artisan serve --host=127.0.0.1 --port=8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCFILE

systemctl daemon-reload
systemctl enable smartcms-api
systemctl restart smartcms-api

info "Laravel API running on 127.0.0.1:8000"

# ============================================================
# VERIFY
# ============================================================
step "Verification"

echo ""
info "Services:"
systemctl is-active --quiet mariadb && echo "  ✅ MariaDB: running" || echo "  ❌ MariaDB: stopped"
systemctl is-active --quiet php8.3-fpm && echo "  ✅ PHP-FPM: running" || echo "  ❌ PHP-FPM: stopped"
systemctl is-active --quiet nginx && echo "  ✅ Nginx: running" || echo "  ❌ Nginx: stopped"
systemctl is-active --quiet smartcms-api && echo "  ✅ Laravel API: running" || echo "  ❌ Laravel API: stopped"
(asterisk -rx "core show version" 2>/dev/null && echo "  ✅ Asterisk: running") || echo "  ❌ Asterisk: not running"

echo ""
info "Database:"
TABLE_COUNT=$(mariadb -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "?")
echo "  Tables: $TABLE_COUNT"
PS_TABLES=$(mariadb -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name LIKE 'ps_%';" 2>/dev/null || echo "?")
echo "  PJSIP Realtime tables: $PS_TABLES"

echo ""
info "Asterisk:"
asterisk -rx "pjsip show transports" 2>/dev/null | head -10 || echo "  (not ready yet)"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          SmartCMS Deployment Complete!                   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  CMS:      http://${EXTERNAL_IP}                        ║"
echo "║  API:      http://${EXTERNAL_IP}/api                    ║"
echo "║                                                          ║"
echo "║  Login:    superadmin@smartcms.local                     ║"
echo "║  Password: SmartCMS@2026                                 ║"
echo "║  License:  SMARTCMS-SA-MASTER-2026                       ║"
echo "║                                                          ║"
echo "║  Asterisk: ${EXTERNAL_IP}:5060 (SIP)                   ║"
echo "║            ${EXTERNAL_IP}:8089 (WSS)                    ║"
echo "║            ${EXTERNAL_IP}:5038 (AMI)                    ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
warn "⚠ Ganti semua password default sebelum production!"
echo ""
