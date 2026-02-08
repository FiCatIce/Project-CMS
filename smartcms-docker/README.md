# SmartCMS - Asterisk Docker Deployment

## Arsitektur

```
103.154.80.173
├── Docker Compose
│   ├── smartcms-db        (MariaDB 11.4)
│   ├── smartcms-asterisk  (Asterisk 21 - Custom Build from Source)
│   ├── smartcms-api       (Laravel PHP)
│   ├── smartcms-frontend  (Angular 17 + Nginx)
│   └── smartcms-redis     (Redis 7 - WebSocket broadcasting)
│
├── Ports
│   ├── 80/443     → Nginx (Frontend + API proxy)
│   ├── 5060       → Asterisk PJSIP (UDP/TCP)
│   ├── 5061       → Asterisk PJSIP TLS
│   ├── 8088       → Asterisk HTTP/WebSocket (WS)
│   ├── 8089       → Asterisk HTTPS/WebSocket (WSS)
│   ├── 5038       → Asterisk AMI
│   ├── 10000-10500 → RTP Media
│   └── 3306       → MariaDB (internal only)
│
└── Volumes
    ├── mariadb_data     → /var/lib/mysql
    ├── asterisk_config  → /etc/asterisk
    ├── asterisk_logs    → /var/log/asterisk
    └── asterisk_spool   → /var/spool/asterisk (recordings)
```

## License System

### Flow
```
User → http://103.154.80.173/license
  ├── GET /api/license/verify → Check if licensed
  │   ├── No  → Show "Enter License Key" form
  │   └── Yes → Redirect to /login
  │
User → /login (setelah license verified)
  ├── POST /api/login → Get auth token
  ├── GET /api/license/modules → Get allowed menu items
  │   ├── super_admin → ALL modules
  │   └── admin → Only licensed modules
  │
User → Navigate to menu
  ├── LicenseGuard checks module access
  │   ├── Allowed → Show page
  │   └── Not allowed → "License not available"
```

### License Types
| Type | Modules | Call Servers | Use Case |
|------|---------|-------------|----------|
| super_admin | ALL | Unlimited | Master admin |
| admin | Limited (by license) | 1 (default) | Customer admin |
| operator | Limited | 1 | Operator |
| viewer | Dashboard only | 0 | Read-only |

## Extension Types & Transport

| Type | Transport | Context | Max Contacts | Use |
|------|-----------|---------|-------------|-----|
| extension | WSS | from-internal | 1 | SIP extension (WebRTC) |
| line | WSS | from-internal | 5 | Turret line |
| vpw | WSS | vpw | 2 | Virtual Private Wire |
| cas | WSS | from-internal | 1 | CAS channel |
| 3rd_party | UDP | from-internal | 1 | IP Phone/Device |
| trunk | UDP | from-pstn | 1 | Outbound trunk |
| sbc | UDP | from-pstn | 1 | SBC/Provider |

### Secret/Password Rules
- **Extension, Line, VPW, CAS**: Secret auto-generated (32 hex chars), NEVER shown in CMS, admin CANNOT edit
- **3rd Party**: Secret auto-generated, same rules
- **Trunk/SBC**: Secret provided by admin (for provider auth)

## Deploy ke Server (103.154.80.173)

### Quick Deploy — 3 Command Saja:
```bash
# 1. Upload file ke server (dari laptop/PC kamu)
scp smartcms-docker.tar.gz root@103.154.80.173:/root/

# 2. SSH ke server
ssh root@103.154.80.173

# 3. Extract dan jalankan deploy script
cd /root && tar xzf smartcms-docker.tar.gz && cd smartcms-docker
chmod +x deploy.sh smartcms.sh
sudo ./deploy.sh
```

Script `deploy.sh` otomatis melakukan:
- ✅ Install Docker & Docker Compose
- ✅ Clone Angular frontend dari GitHub
- ✅ Create Laravel backend + integrate license module
- ✅ Generate SSL certificate (self-signed)
- ✅ Build Asterisk 21 dari source (~20 menit)
- ✅ Start semua containers
- ✅ Import database schema + PJSIP realtime tables
- ✅ Create super admin user

### Management (setelah deploy)
```bash
cd /opt/smartcms
./smartcms.sh status           # Cek container status
./smartcms.sh asterisk         # Masuk Asterisk CLI
./smartcms.sh show-extensions  # Lihat semua extension
./smartcms.sh logs asterisk    # Log Asterisk
./smartcms.sh db               # Masuk MariaDB CLI
./smartcms.sh backup-db        # Backup database
./smartcms.sh update-frontend  # Pull & rebuild Angular
```

## Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| CMS Super Admin | superadmin@smartcms.local | SmartCMS@2026 |
| License Key (SA) | SMARTCMS-SA-MASTER-2026 | - |
| MariaDB root | root | SmartCMS_Root_2026! |
| MariaDB app | smartcms | SmartCMS_DB_2026! |
| AMI | smartcms | smartcms_ami_secret_2026 |
| ARI | smartcms | smartcms_ari_secret_2026 |

⚠️ **GANTI SEMUA PASSWORD SEBELUM PRODUCTION!**

## Realtime Architecture

```
CMS (Laravel) ──create extension──→ MariaDB (ps_endpoints, ps_auths, ps_aors)
                                         ↑
Asterisk ──────reads realtime────────────┘
                                         │
CMS (Laravel) ──AMI: pjsip reload──→ Asterisk (applies changes)
```

Setiap create/update/delete extension di CMS:
1. Laravel insert/update ke tabel `ps_endpoints`, `ps_auths`, `ps_aors`
2. Laravel kirim AMI command `pjsip reload` ke Asterisk
3. Asterisk baca ulang dari DB (realtime) — perubahan langsung aktif

## File Structure

```
smartcms-docker/
├── docker-compose.yml              # Main compose file
├── .env                            # Environment variables
│
├── asterisk/
│   ├── Dockerfile                  # Custom Asterisk build from source
│   ├── entrypoint.sh               # Startup script (ODBC config, wait for DB)
│   └── configs/
│       ├── asterisk.conf           # Main config
│       ├── pjsip.conf              # PJSIP transports (WSS, UDP, TCP)
│       ├── sorcery.conf            # Maps PJSIP → ODBC realtime
│       ├── extconfig.conf          # ODBC table mappings
│       ├── res_odbc.conf           # ODBC connection to MariaDB
│       ├── extensions.conf         # Dialplan
│       ├── manager.conf            # AMI config
│       ├── http.conf               # HTTP/WebSocket server
│       ├── ari.conf                # ARI REST API
│       ├── modules.conf            # Module loading
│       ├── rtp.conf                # RTP port range
│       └── cdr_odbc.conf           # CDR to database
│
├── scripts/
│   ├── setup.sh                    # Deployment script
│   └── 001_pjsip_realtime_and_license.sql  # DB migration
│
├── cms/
│   ├── license-module/             # Laravel license system
│   │   ├── Models/License.php
│   │   ├── Models/LicenseActivation.php
│   │   ├── Controllers/LicenseController.php
│   │   ├── Middleware/CheckLicense.php
│   │   └── Routes/license.php
│   │
│   ├── asterisk-realtime/          # Asterisk realtime integration
│   │   ├── Services/AsteriskRealtimeService.php
│   │   └── config_asterisk.php
│   │
│   └── angular-license/            # Angular frontend license module
│       └── license-module.ts       # Service + Guard + routing example
│
├── mariadb/
│   └── my.cnf                      # MariaDB custom config
│
└── nginx/
    └── default.conf                # Nginx reverse proxy config
```

## API Endpoints

### License (Public)
- `GET /api/license/verify` — Check server license
- `POST /api/license/activate` — Activate license key

### License (Authenticated)
- `GET /api/license/modules` — Get user's allowed modules
- `POST /api/license/check-module` — Check specific module access

### License Management (Super Admin)
- `GET /api/licenses` — List all licenses
- `POST /api/licenses` — Create license
- `PUT /api/licenses/{id}` — Update license
- `DELETE /api/licenses/{id}` — Revoke license

## Next Steps

1. ✅ Docker Asterisk custom build
2. ✅ License system (DB + API + Angular guard)
3. ✅ PJSIP realtime (extensions via DB)
4. ⬜ Deploy ke 103.154.80.173
5. ⬜ Test create extension → register → call
6. ⬜ Test trunk/SBC connectivity
7. ⬜ Integrate license checks ke semua existing routes
8. ⬜ Turret module (speaker bus, IPC)
