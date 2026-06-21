-- ============================================================================
--  OpenSIPS Teams SBC -- database schema (MySQL / MariaDB)
--  Tables: version, tls_mgm (TLS certs + tenant registry), address (trusted
--          core source IPs).
--
--  OpenSIPS aborts at start-up if a module table's version does not match, so
--  the `version` rows below are mandatory:
--      tls_mgm -> 3
--      address -> 5
--
--  Apply with:   mysql opensips < sql/01-schema.sql
-- ============================================================================

CREATE TABLE IF NOT EXISTS version (
    table_name    VARCHAR(32)  NOT NULL,
    table_version INT UNSIGNED NOT NULL DEFAULT 0,
    UNIQUE KEY version_t_name_idx (table_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
--  tls_mgm  (table version 3) -- also the authoritative TENANT registry.
--  A tenant = a row whose `domain` and `match_sip_domain` are the tenant FQDN.
--  type: 0 = client+server, 1 = client only, 2 = server only.
--    teams_srv (type 2, matched by IP)   -> inbound TLS terminator on :5560
--    teams_cli (type 1, match_ip '*')    -> SBC -> Microsoft client identity
--    <tenant>  (type 2, match_sip_domain)-> per-tenant cert selected by TLS SNI
--  certificate / private_key / ca_list are PEM BLOBs (ca_list = the public CA
--  bundle used to verify Microsoft, not our own issuer).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tls_mgm (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    domain           CHAR(64)     NOT NULL DEFAULT '',
    match_ip_address VARCHAR(255) DEFAULT NULL,
    match_sip_domain VARCHAR(255) DEFAULT NULL,
    type             INT          NOT NULL DEFAULT 1,
    method           VARCHAR(64)  DEFAULT 'SSLv23',
    verify_cert      INT          DEFAULT 1,
    require_cert     INT          DEFAULT 1,
    certificate      BLOB,
    private_key      BLOB,
    crl_check_all    INT          DEFAULT 0,
    crl_dir          VARCHAR(255) DEFAULT NULL,
    ca_list          MEDIUMBLOB,
    ca_dir           VARCHAR(255) DEFAULT NULL,
    cipher_list      VARCHAR(255) DEFAULT NULL,
    dh_params        BLOB,
    ec_curve         VARCHAR(255) DEFAULT NULL,
    UNIQUE KEY domain_type_idx (domain, type),
    KEY match_sip_domain_idx (match_sip_domain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
--  address  (table version 5) -- trusted source IPs for the permissions module.
--  Group M_CORE_GROUP (default 1) holds the core node IPs; the rotation sidecar
--  refreshes them from DNS (ips.ucp.voiceland.global / eu.ucp.voiceland.dev)
--  every 5 minutes and runs MI `address_reload`.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS address (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    grp          SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    ip           VARCHAR(50)       NOT NULL,
    mask         SMALLINT UNSIGNED NOT NULL DEFAULT 32,
    port         SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    proto        VARCHAR(4)        NOT NULL DEFAULT 'any',
    pattern      VARCHAR(64)       DEFAULT NULL,
    context_info VARCHAR(32)       DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO version (table_name, table_version) VALUES ('tls_mgm', 3)
    ON DUPLICATE KEY UPDATE table_version = 3;
INSERT INTO version (table_name, table_version) VALUES ('address', 5)
    ON DUPLICATE KEY UPDATE table_version = 5;
