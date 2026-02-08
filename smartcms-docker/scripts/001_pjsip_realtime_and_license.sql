-- ============================================================
-- SmartCMS Database Migration
-- PJSIP Realtime Tables + License System
-- Run on: db_ucx (MariaDB)
-- ============================================================

-- ============================================================
-- 1. LICENSE SYSTEM
-- ============================================================

-- License table - stores license keys and module access
DROP TABLE IF EXISTS `licenses`;
CREATE TABLE `licenses` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `license_key` varchar(255) NOT NULL COMMENT 'Unique license key',
  `company_name` varchar(255) DEFAULT NULL,
  `license_type` enum('super_admin','admin','operator','viewer') NOT NULL DEFAULT 'admin',
  `max_extensions` int(11) DEFAULT 100 COMMENT 'Maximum extensions allowed',
  `max_trunks` int(11) DEFAULT 10 COMMENT 'Maximum trunks allowed',
  `max_call_servers` int(11) DEFAULT 1 COMMENT 'Max call servers (admin=1)',
  `allowed_modules` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'JSON array of allowed menu modules',
  `hardware_id` varchar(255) DEFAULT NULL COMMENT 'Bound to server hardware ID',
  `issued_at` timestamp NULL DEFAULT current_timestamp(),
  `expires_at` timestamp NULL DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `created_by` int(11) DEFAULT NULL COMMENT 'Created by super_admin user ID',
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `license_key` (`license_key`),
  CONSTRAINT `licenses_chk_1` CHECK (json_valid(`allowed_modules`) OR `allowed_modules` IS NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- License activation log
DROP TABLE IF EXISTS `license_activations`;
CREATE TABLE `license_activations` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `license_id` int(11) NOT NULL,
  `activated_by` int(11) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `hostname` varchar(255) DEFAULT NULL,
  `hardware_id` varchar(255) DEFAULT NULL,
  `status` enum('activated','deactivated','expired','revoked') DEFAULT 'activated',
  `activated_at` timestamp NULL DEFAULT current_timestamp(),
  `deactivated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `license_id` (`license_id`),
  CONSTRAINT `license_activations_ibfk_1` FOREIGN KEY (`license_id`) REFERENCES `licenses` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Add license_id to cms_users
ALTER TABLE `cms_users` 
  ADD COLUMN `license_id` int(11) DEFAULT NULL AFTER `is_active`,
  ADD COLUMN `is_super_admin` tinyint(1) DEFAULT 0 AFTER `role`,
  ADD KEY `license_id` (`license_id`);

-- Default super admin license (all access)
INSERT INTO `licenses` (`license_key`, `company_name`, `license_type`, `max_extensions`, `max_trunks`, `max_call_servers`, `allowed_modules`, `is_active`, `created_at`) VALUES
('SMARTCMS-SA-MASTER-2026', 'SmartCMS Master', 'super_admin', 99999, 99999, 99999, 
'["dashboard","extensions","lines","vpws","cas","3rd_party","trunks","sbcs","inbound_routes","outbound_routes","ring_groups","ivr","conferences","announcements","recordings","time_conditions","blacklists","phone_directory","firewall","static_routes","call_servers","customers","head_offices","branches","sub_branches","cms_users","cms_groups","turret_users","turret_groups","turret_policies","turret_templates","sbc_routes","dahdi","intercoms","activity_logs","system_logs","cdrs","usage_statistics","settings","license_management"]',
1, NOW());

-- Example admin license (limited modules)  
INSERT INTO `licenses` (`license_key`, `company_name`, `license_type`, `max_extensions`, `max_trunks`, `max_call_servers`, `allowed_modules`, `is_active`, `created_at`) VALUES
('SMARTCMS-ADM-DEMO-2026', 'Demo Admin', 'admin', 50, 5, 1,
'["dashboard","extensions","lines","vpws","cas","3rd_party","trunks","inbound_routes","outbound_routes","ring_groups","ivr","conferences","cdrs"]',
1, NOW());

-- ============================================================
-- 2. PJSIP REALTIME TABLES (Asterisk 21)
-- ============================================================

-- PS Endpoints - main PJSIP endpoint table
DROP TABLE IF EXISTS `ps_endpoints`;
CREATE TABLE `ps_endpoints` (
  `id` varchar(40) NOT NULL COMMENT 'Extension number (e.g., 1001)',
  `transport` varchar(40) DEFAULT 'transport-wss' COMMENT 'wss for ext/line/vpw/cas, udp for 3rd party',
  `aors` varchar(200) DEFAULT NULL COMMENT 'Matching AOR id',
  `auth` varchar(40) DEFAULT NULL COMMENT 'Matching Auth id',
  `context` varchar(40) DEFAULT 'from-internal' COMMENT 'Dialplan context',
  `disallow` varchar(200) DEFAULT 'all',
  `allow` varchar(200) DEFAULT 'opus,ulaw,alaw',
  `direct_media` enum('yes','no') DEFAULT 'no',
  `connected_line_method` varchar(40) DEFAULT 'invite',
  `direct_media_method` varchar(40) DEFAULT 'invite',
  `direct_media_glare_mitigation` varchar(40) DEFAULT 'none',
  `disable_direct_media_on_nat` enum('yes','no') DEFAULT 'yes',
  `dtmf_mode` varchar(40) DEFAULT 'rfc4733',
  `external_media_address` varchar(40) DEFAULT NULL,
  `force_rport` enum('yes','no') DEFAULT 'yes',
  `ice_support` enum('yes','no') DEFAULT 'yes',
  `identify_by` varchar(80) DEFAULT 'username',
  `mailboxes` varchar(40) DEFAULT NULL,
  `max_audio_streams` int(11) DEFAULT 1,
  `max_video_streams` int(11) DEFAULT 1,
  `moh_suggest` varchar(40) DEFAULT 'default',
  `outbound_auth` varchar(40) DEFAULT NULL,
  `rewrite_contact` enum('yes','no') DEFAULT 'yes',
  `rtp_symmetric` enum('yes','no') DEFAULT 'yes',
  `send_diversion` enum('yes','no') DEFAULT 'yes',
  `send_pai` enum('yes','no') DEFAULT 'yes',
  `send_rpid` enum('yes','no') DEFAULT 'yes',
  `100rel` varchar(40) DEFAULT 'no',
  `trust_id_inbound` enum('yes','no') DEFAULT 'no',
  `trust_id_outbound` enum('yes','no') DEFAULT 'no',
  `use_ptime` enum('yes','no') DEFAULT 'no',
  `use_avpf` enum('yes','no') DEFAULT 'yes' COMMENT 'Required for WebRTC',
  `media_encryption` varchar(40) DEFAULT 'dtls' COMMENT 'dtls for WSS, no for UDP',
  `media_encryption_optimistic` enum('yes','no') DEFAULT 'yes',
  `inband_progress` enum('yes','no') DEFAULT 'no',
  `call_group` varchar(40) DEFAULT NULL,
  `pickup_group` varchar(40) DEFAULT NULL,
  `named_call_group` varchar(40) DEFAULT NULL,
  `named_pickup_group` varchar(40) DEFAULT NULL,
  `device_state_busy_at` int(11) DEFAULT 1,
  `t38_udptl` enum('yes','no') DEFAULT 'no',
  `t38_udptl_ec` varchar(40) DEFAULT 'none',
  `t38_udptl_maxdatagram` int(11) DEFAULT 0,
  `fax_detect` enum('yes','no') DEFAULT 'no',
  `t38_udptl_nat` enum('yes','no') DEFAULT 'no',
  `record_on_feature` varchar(40) DEFAULT 'automixmon',
  `record_off_feature` varchar(40) DEFAULT 'automixmon',
  `accountcode` varchar(80) DEFAULT NULL,
  `callerid` varchar(200) DEFAULT NULL COMMENT 'CallerID format: "Name" <number>',
  `callerid_privacy` varchar(40) DEFAULT NULL,
  `callerid_tag` varchar(40) DEFAULT NULL,
  `webrtc` enum('yes','no') DEFAULT 'yes' COMMENT 'Enable WebRTC shortcuts',
  `dtls_auto_generate_cert` enum('yes','no') DEFAULT 'yes',
  `allow_subscribe` enum('yes','no') DEFAULT 'yes',
  `sub_min_expiry` int(11) DEFAULT 60,
  `from_user` varchar(40) DEFAULT NULL,
  `from_domain` varchar(40) DEFAULT NULL,
  `mwi_from_user` varchar(40) DEFAULT NULL,
  `language` varchar(40) DEFAULT 'en',
  `tone_zone` varchar(40) DEFAULT NULL,
  `voicemail_extension` varchar(40) DEFAULT NULL,
  -- SmartCMS custom columns
  `smartcms_type` varchar(20) DEFAULT 'extension' COMMENT 'extension|line|vpw|cas|3rd_party|trunk|sbc',
  `smartcms_call_server_id` int(11) DEFAULT NULL,
  `smartcms_created_at` timestamp NULL DEFAULT current_timestamp(),
  `smartcms_updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- PS Auths - authentication for endpoints
DROP TABLE IF EXISTS `ps_auths`;
CREATE TABLE `ps_auths` (
  `id` varchar(40) NOT NULL COMMENT 'Same as endpoint id',
  `auth_type` varchar(40) DEFAULT 'userpass',
  `nonce_lifetime` int(11) DEFAULT 32,
  `md5_cred` varchar(40) DEFAULT NULL,
  `password` varchar(80) NOT NULL COMMENT 'SIP password (auto-generated, not shown in CMS)',
  `realm` varchar(40) DEFAULT NULL,
  `username` varchar(40) NOT NULL COMMENT 'Same as endpoint id',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- PS AORs (Address of Record) - registration settings
DROP TABLE IF EXISTS `ps_aors`;
CREATE TABLE `ps_aors` (
  `id` varchar(40) NOT NULL COMMENT 'Same as endpoint id',
  `contact` varchar(255) DEFAULT NULL,
  `default_expiration` int(11) DEFAULT 3600,
  `mailboxes` varchar(80) DEFAULT NULL,
  `max_contacts` int(11) DEFAULT 1 COMMENT '1 for extensions, more for shared lines',
  `minimum_expiration` int(11) DEFAULT 60,
  `maximum_expiration` int(11) DEFAULT 7200,
  `remove_existing` enum('yes','no') DEFAULT 'yes',
  `qualify_frequency` int(11) DEFAULT 60,
  `qualify_timeout` float DEFAULT 3.0,
  `authenticate_qualify` enum('yes','no') DEFAULT 'no',
  `outbound_proxy` varchar(256) DEFAULT NULL,
  `support_path` enum('yes','no') DEFAULT 'no',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- PS Contacts - dynamic contacts (filled by Asterisk when devices register)
DROP TABLE IF EXISTS `ps_contacts`;
CREATE TABLE `ps_contacts` (
  `id` varchar(255) NOT NULL,
  `uri` varchar(255) NOT NULL,
  `expiration_time` bigint(20) DEFAULT NULL,
  `qualify_frequency` int(11) DEFAULT 0,
  `qualify_timeout` float DEFAULT 3.0,
  `authenticate_qualify` enum('yes','no') DEFAULT 'no',
  `outbound_proxy` varchar(256) DEFAULT NULL,
  `path` text DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `endpoint` varchar(40) DEFAULT NULL,
  `reg_server` varchar(20) DEFAULT NULL,
  `via_addr` varchar(40) DEFAULT NULL,
  `via_port` int(11) DEFAULT 0,
  `call_id` varchar(255) DEFAULT NULL,
  `prune_on_boot` enum('yes','no') DEFAULT 'yes',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- PS Registrations - outbound registration (for trunks/SBCs)
DROP TABLE IF EXISTS `ps_registrations`;
CREATE TABLE `ps_registrations` (
  `id` varchar(40) NOT NULL COMMENT 'Trunk/SBC name',
  `auth_rejection_permanent` enum('yes','no') DEFAULT 'yes',
  `client_uri` varchar(255) DEFAULT NULL,
  `contact_user` varchar(40) DEFAULT NULL,
  `expiration` int(11) DEFAULT 3600,
  `max_retries` int(11) DEFAULT 10,
  `outbound_auth` varchar(40) DEFAULT NULL,
  `outbound_proxy` varchar(256) DEFAULT NULL,
  `retry_interval` int(11) DEFAULT 60,
  `forbidden_retry_interval` int(11) DEFAULT 0,
  `server_uri` varchar(255) DEFAULT NULL,
  `transport` varchar(40) DEFAULT 'transport-udp',
  `line` enum('yes','no') DEFAULT 'no',
  `endpoint` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- PS Endpoint ID by IP - identify endpoints by IP (for trunks/SBCs)
DROP TABLE IF EXISTS `ps_endpoint_id_ips`;
CREATE TABLE `ps_endpoint_id_ips` (
  `id` varchar(40) NOT NULL,
  `endpoint` varchar(40) NOT NULL,
  `match` varchar(80) NOT NULL COMMENT 'IP/CIDR to match',
  `srv_lookups` enum('yes','no') DEFAULT 'yes',
  `match_header` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- PS Domain Aliases
DROP TABLE IF EXISTS `ps_domain_aliases`;
CREATE TABLE `ps_domain_aliases` (
  `id` varchar(40) NOT NULL,
  `domain` varchar(80) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 3. INDEXES FOR PERFORMANCE
-- ============================================================

CREATE INDEX idx_ps_endpoints_type ON ps_endpoints(smartcms_type);
CREATE INDEX idx_ps_endpoints_server ON ps_endpoints(smartcms_call_server_id);
CREATE INDEX idx_ps_contacts_endpoint ON ps_contacts(endpoint);
CREATE INDEX idx_licenses_key ON licenses(license_key);
CREATE INDEX idx_licenses_type ON licenses(license_type);
