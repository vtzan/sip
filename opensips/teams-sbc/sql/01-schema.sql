-- ============================================================================
--  OpenSIPS Teams SBC -- database schema (MySQL / MariaDB)
--  Tables: version, domain (allowed tenant domains), tls_mgm (TLS certificates)
--
--  OpenSIPS aborts at start-up if a module table's version does not match the
--  value it expects, so the `version` rows below are mandatory:
--      domain  -> 4
--      tls_mgm -> 3
--
--  Apply with:
--      mysql opensips < sql/01-schema.sql
--  (or let `opensips-cli -o database create` build the full standard schema and
--   use this file only as a reference for the two tables we rely on.)
-- ============================================================================

CREATE TABLE IF NOT EXISTS version (
    table_name    VARCHAR(32)  NOT NULL,
    table_version INT UNSIGNED NOT NULL DEFAULT 0,
    UNIQUE KEY version_t_name_idx (table_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
--  domain module  (table version 4)
--  `domain` = a permitted tenant FQDN.
--  `attrs`  = the inbound carrier trunk SIP URI for that tenant, e.g.
--             sip:198.51.100.10:5060            (UDP, default)
--             sip:198.51.100.10:5060;transport=tcp
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS domain (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    domain           VARCHAR(64)  NOT NULL DEFAULT '',
    attrs            VARCHAR(255) DEFAULT NULL,
    accept_subdomain INT UNSIGNED NOT NULL DEFAULT 0,
    last_modified    DATETIME     NOT NULL DEFAULT '1900-01-01 00:00:01',
    UNIQUE KEY domain_idx (domain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
--  tls_mgm module  (table version 3)
--  type: 0 = client+server, 1 = client only, 2 = server only
--  Inbound TLS (Teams -> SBC :5560) is matched by match_ip_address.
--  Per-tenant certs (optional) are matched by match_sip_domain (TLS SNI).
--  certificate / private_key / ca_list hold PEM content as BLOBs.
--  ca_list = the PUBLIC CA bundle used to verify the Microsoft peer cert
--            (NOT the issuer chain of our own certificate).
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
    UNIQUE KEY domain_type_idx (domain, type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO version (table_name, table_version) VALUES ('domain', 4)
    ON DUPLICATE KEY UPDATE table_version = 4;
INSERT INTO version (table_name, table_version) VALUES ('tls_mgm', 3)
    ON DUPLICATE KEY UPDATE table_version = 3;
