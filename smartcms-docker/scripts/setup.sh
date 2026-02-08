#!/bin/bash
# ============================================================
# SmartCMS Setup & Deployment Script
# Run on: 103.154.80.173 (Debian)
# ============================================================

set -e

echo "======================================"
echo " SmartCMS Setup Script"
echo " Server: 103.154.80.173"
echo "======================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# Step 1: Install Docker & Docker Compose
# ============================================================
install_docker() {
    info "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        info "Docker already installed: $(docker --version)"
    else
        apt-get update
        apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable docker
        systemctl start docker
        info "Docker installed successfully"
    fi
}

# ============================================================
# Step 2: Clone SmartCMS repo
# ============================================================
clone_repo() {
    info "Setting up project directory..."

    PROJECT_DIR="/opt/smartcms"
    
    if [ -d "$PROJECT_DIR" ]; then
        warn "Project directory exists. Backing up..."
        cp -r "$PROJECT_DIR" "${PROJECT_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    mkdir -p "$PROJECT_DIR"
    
    # Clone Angular frontend
    if [ ! -d "$PROJECT_DIR/frontend" ]; then
        info "Cloning SmartCMS Angular frontend..."
        git clone https://github.com/rhaaf-project/SmartCMS-Angular-171.git "$PROJECT_DIR/frontend"
    fi

    # Copy Docker configs
    info "Copying Docker configuration..."
    cp -r ./asterisk "$PROJECT_DIR/"
    cp -r ./mariadb "$PROJECT_DIR/"
    cp -r ./nginx "$PROJECT_DIR/"
    cp -r ./scripts "$PROJECT_DIR/"
    cp -r ./cms "$PROJECT_DIR/"
    cp docker-compose.yml "$PROJECT_DIR/"
    cp .env "$PROJECT_DIR/"
    
    info "Project setup at $PROJECT_DIR"
}

# ============================================================
# Step 3: Generate SSL certificates (self-signed)
# ============================================================
generate_ssl() {
    info "Generating self-signed SSL certificates..."
    
    SSL_DIR="/opt/smartcms/asterisk/keys"
    mkdir -p "$SSL_DIR"
    mkdir -p "/opt/smartcms/nginx/ssl"

    # Generate for Asterisk (WSS)
    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout "$SSL_DIR/asterisk.key" \
        -out "$SSL_DIR/asterisk.pem" \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=SmartCMS/CN=103.154.80.173"

    # Generate for Nginx (HTTPS)
    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout "/opt/smartcms/nginx/ssl/privkey.pem" \
        -out "/opt/smartcms/nginx/ssl/fullchain.pem" \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=SmartCMS/CN=103.154.80.173"

    # Combine cert for Asterisk (some configs need combined PEM)
    cat "$SSL_DIR/asterisk.pem" "$SSL_DIR/asterisk.key" > "$SSL_DIR/asterisk-combined.pem"

    chmod 644 "$SSL_DIR"/*.pem "$SSL_DIR"/*.key
    chmod 644 /opt/smartcms/nginx/ssl/*.pem

    info "SSL certificates generated"
}

# ============================================================
# Step 4: Generate Laravel APP_KEY
# ============================================================
generate_app_key() {
    info "Generating Laravel APP_KEY..."
    
    APP_KEY=$(openssl rand -base64 32)
    sed -i "s|APP_KEY=.*|APP_KEY=base64:${APP_KEY}|" /opt/smartcms/.env
    
    info "APP_KEY generated"
}

# ============================================================
# Step 5: Build and start services
# ============================================================
build_and_start() {
    info "Building Docker images..."
    cd /opt/smartcms

    # Build Asterisk (this takes a while - compiling from source)
    info "Building custom Asterisk (this may take 15-30 minutes)..."
    docker compose build asterisk

    # Build other services
    docker compose build

    # Start services
    info "Starting all services..."
    docker compose up -d

    # Wait for MariaDB to be ready
    info "Waiting for MariaDB to be ready..."
    sleep 10

    # Run SQL migrations
    info "Running database migrations..."
    docker compose exec -T mariadb mysql -u root -p"${DB_ROOT_PASSWORD:-SmartCMS_Root_2026\!}" db_ucx < scripts/001_pjsip_realtime_and_license.sql 2>/dev/null || true

    info "All services started!"
}

# ============================================================
# Step 6: Create default super admin
# ============================================================
create_super_admin() {
    info "Creating default super admin user..."
    
    docker compose exec -T mariadb mysql -u root -p"${DB_ROOT_PASSWORD:-SmartCMS_Root_2026\!}" db_ucx << 'SQL'
INSERT INTO cms_users (name, email, password, role, is_super_admin, license_id, is_active, created_at, updated_at)
VALUES (
    'Super Admin',
    'superadmin@smartcms.local',
    '$2y$12$sZmwDnKqS3Y9vGPKOIKFe.UrYR4VLrfg2VLxJq7RRJw7C0I1GwVhm',
    'admin',
    1,
    1,
    1,
    NOW(),
    NOW()
)
ON DUPLICATE KEY UPDATE is_super_admin = 1, license_id = 1;
SQL
    # Default password: SmartCMS@2026
    
    info "Super admin created:"
    info "  Email: superadmin@smartcms.local"
    info "  Password: SmartCMS@2026"
    warn "  CHANGE THIS PASSWORD IMMEDIATELY!"
}

# ============================================================
# Step 7: Verify installation
# ============================================================
verify() {
    echo ""
    echo "======================================"
    echo " Verification"
    echo "======================================"
    
    # Check containers
    info "Container status:"
    docker compose ps

    echo ""
    
    # Check Asterisk
    info "Asterisk status:"
    docker compose exec asterisk asterisk -rx "core show version" 2>/dev/null || warn "Asterisk not ready yet"
    
    echo ""
    info "PJSIP transports:"
    docker compose exec asterisk asterisk -rx "pjsip show transports" 2>/dev/null || warn "PJSIP not ready yet"

    echo ""
    echo "======================================"
    echo " SmartCMS Deployment Complete!"
    echo "======================================"
    echo ""
    info "Access URLs:"
    info "  CMS Frontend:  http://103.154.80.173"
    info "  CMS API:       http://103.154.80.173/api"
    info "  License Page:  http://103.154.80.173/license"
    info "  WebSocket:     ws://103.154.80.173:8088/ws"
    info "  WSS:           wss://103.154.80.173:8089/ws"
    echo ""
    info "Default Super Admin:"
    info "  Email:    superadmin@smartcms.local"
    info "  Password: SmartCMS@2026"
    info "  License:  SMARTCMS-SA-MASTER-2026"
    echo ""
    info "Asterisk AMI: 103.154.80.173:5038"
    info "Asterisk ARI: http://103.154.80.173:8088"
    info "SIP/PJSIP:    103.154.80.173:5060 (UDP/TCP)"
    echo ""
    warn "Don't forget to:"
    warn "  1. Change default passwords"
    warn "  2. Setup proper SSL certificates"
    warn "  3. Configure firewall rules"
    warn "  4. Assign licenses to admin users"
}

# ============================================================
# Main
# ============================================================
case "${1:-all}" in
    docker)
        install_docker
        ;;
    clone)
        clone_repo
        ;;
    ssl)
        generate_ssl
        ;;
    build)
        build_and_start
        ;;
    admin)
        create_super_admin
        ;;
    verify)
        verify
        ;;
    all)
        install_docker
        clone_repo
        generate_ssl
        generate_app_key
        build_and_start
        create_super_admin
        verify
        ;;
    *)
        echo "Usage: $0 {docker|clone|ssl|build|admin|verify|all}"
        exit 1
        ;;
esac
