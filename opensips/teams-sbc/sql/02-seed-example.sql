-- ============================================================================
--  OpenSIPS Teams SBC -- base TLS rows (idempotent).
--  Run by the container entrypoint on first boot; safe to re-run.
--      mysql opensips < sql/02-seed-example.sql
--
--  Certificates/keys start NULL and are filled by the first-boot bootstrap
--  (self-signed) and then by tls-rotation/manage-tls.py (ACME). match_ip_address
--  on the server row MUST equal the SBC TLS listen IP:port from local.m4
--  (M_TEAMS_TLS_LISTEN_IP:M_TEAMS_TLS_PORT).
--
--  Per-tenant rows are created with scripts/create-tenant.sh, NOT here.
-- ============================================================================

INSERT INTO tls_mgm
    (domain, type, match_ip_address, match_sip_domain, method, verify_cert, require_cert, cipher_list)
VALUES
    -- inbound TLS terminator (mutual TLS with Microsoft)
    ('teams_srv', 2, '10.0.0.10:5560', NULL, 'TLSv1_2+', 1, 1,
     'HIGH:!aNULL:!eNULL:!MD5:!RC4:!3DES:!EXPORT'),
    -- SBC -> Microsoft client identity
    ('teams_cli', 1, '*',             NULL, 'TLSv1_2+', 1, 0,
     'HIGH:!aNULL:!eNULL:!MD5:!RC4:!3DES:!EXPORT')
ON DUPLICATE KEY UPDATE method = VALUES(method), cipher_list = VALUES(cipher_list);
