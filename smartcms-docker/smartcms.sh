#!/bin/bash
# ============================================================
# SmartCMS Management Helper
# Usage: ./smartcms.sh <command>
# ============================================================

PROJECT_DIR="/opt/smartcms"
cd "$PROJECT_DIR" 2>/dev/null || { echo "Project not found at $PROJECT_DIR"; exit 1; }

case "${1}" in
    status|ps)
        docker compose ps
        ;;
    start)
        docker compose up -d
        echo "All services started"
        ;;
    stop)
        docker compose down
        echo "All services stopped"
        ;;
    restart)
        docker compose restart ${2:-}
        ;;
    logs)
        docker compose logs -f --tail=100 ${2:-}
        ;;
    asterisk|ast)
        # Asterisk CLI
        docker exec -it smartcms-asterisk asterisk -rvvv
        ;;
    ast-cmd)
        # Run single Asterisk command
        shift
        docker exec smartcms-asterisk asterisk -rx "$*"
        ;;
    db|mysql)
        # MariaDB CLI
        source .env
        docker exec -it smartcms-db mysql -u root -p"${DB_ROOT_PASSWORD}" db_ucx
        ;;
    api-logs)
        docker compose logs -f --tail=200 cms-api
        ;;
    rebuild)
        # Rebuild specific service
        SERVICE=${2:-cms-frontend}
        docker compose build --no-cache "$SERVICE"
        docker compose up -d "$SERVICE"
        echo "$SERVICE rebuilt and restarted"
        ;;
    pjsip-reload)
        docker exec smartcms-asterisk asterisk -rx "pjsip reload"
        echo "PJSIP reloaded"
        ;;
    show-extensions)
        docker exec smartcms-asterisk asterisk -rx "pjsip show endpoints"
        ;;
    show-registrations)
        docker exec smartcms-asterisk asterisk -rx "pjsip show contacts"
        ;;
    show-trunks)
        docker exec smartcms-asterisk asterisk -rx "pjsip show registrations"
        ;;
    show-channels)
        docker exec smartcms-asterisk asterisk -rx "core show channels"
        ;;
    import-schema)
        source .env
        echo "Importing base schema..."
        docker exec -i smartcms-db mysql -u root -p"${DB_ROOT_PASSWORD}" db_ucx < scripts/schema_lengkap.sql
        echo "Importing PJSIP + License tables..."
        docker exec -i smartcms-db mysql -u root -p"${DB_ROOT_PASSWORD}" db_ucx < scripts/001_pjsip_realtime_and_license.sql
        echo "Done!"
        ;;
    update-frontend)
        echo "Pulling latest frontend..."
        cd frontend && git pull && cd ..
        docker compose build --no-cache cms-frontend
        docker compose up -d cms-frontend
        echo "Frontend updated!"
        ;;
    backup-db)
        source .env
        BACKUP_FILE="backup_db_ucx_$(date +%Y%m%d_%H%M%S).sql"
        docker exec smartcms-db mysqldump -u root -p"${DB_ROOT_PASSWORD}" db_ucx > "$BACKUP_FILE"
        echo "Database backed up to: $BACKUP_FILE"
        ;;
    *)
        echo "SmartCMS Management Tool"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "General:"
        echo "  status          Show container status"
        echo "  start           Start all services"
        echo "  stop            Stop all services"
        echo "  restart [svc]   Restart all or specific service"
        echo "  logs [svc]      Show logs (follow)"
        echo "  rebuild [svc]   Rebuild & restart a service"
        echo ""
        echo "Asterisk:"
        echo "  asterisk        Open Asterisk CLI"
        echo "  ast-cmd <cmd>   Run Asterisk command"
        echo "  pjsip-reload    Reload PJSIP config"
        echo "  show-extensions Show all PJSIP endpoints"
        echo "  show-registrations  Show registered contacts"
        echo "  show-trunks     Show trunk registrations"
        echo "  show-channels   Show active calls"
        echo ""
        echo "Database:"
        echo "  db              Open MariaDB CLI"
        echo "  import-schema   Import SQL schemas"
        echo "  backup-db       Backup database to file"
        echo ""
        echo "Frontend:"
        echo "  update-frontend Pull & rebuild Angular"
        ;;
esac
