-- ============================================================================
--  OpenSIPS Teams SBC -- example seed data
--  Edit the IPs / FQDNs to match your deployment, then:
--      mysql opensips < sql/02-seed-example.sql
--  Reload into a running OpenSIPS without restart:
--      opensips-cli -x mi domain:reload
--      opensips-cli -x mi tls_mgm:reload
-- ============================================================================

-- ---- Allowed tenant domains (attrs = inbound carrier trunk SIP URI) ----
INSERT INTO domain (domain, attrs, accept_subdomain, last_modified) VALUES
    ('acme.teams.ucp.voiceland.dev',    'sip:198.51.100.10:5060', 0, NOW()),
    ('contoso.teams.ucp.voiceland.dev', 'sip:198.51.100.20:5060', 0, NOW())
ON DUPLICATE KEY UPDATE attrs = VALUES(attrs), last_modified = NOW();

-- ---- TLS domains -----------------------------------------------------------
--  Certificates/keys are populated by tls-rotation/manage-tls.py (they start
--  NULL here). match_ip_address on the server row MUST equal the SBC TLS listen
--  IP:port from local.m4 (M_TEAMS_TLS_LISTEN_IP:M_TEAMS_TLS_PORT).
--
--  type 2 = server  (terminates inbound TLS from Teams on :5560, mutual TLS)
--  type 1 = client  (SBC -> sip*.pstnhub.microsoft.com, presents SBC cert)
INSERT INTO tls_mgm
    (domain, type, match_ip_address, match_sip_domain, method, verify_cert, require_cert, cipher_list)
VALUES
    ('teams_srv', 2, '10.0.0.10:5560', NULL, 'TLSv1_2+', 1, 1,
     'HIGH:!aNULL:!eNULL:!MD5:!RC4:!3DES:!EXPORT'),
    ('teams_cli', 1, '*',             NULL, 'TLSv1_2+', 1, 0,
     'HIGH:!aNULL:!eNULL:!MD5:!RC4:!3DES:!EXPORT')
ON DUPLICATE KEY UPDATE method = VALUES(method), cipher_list = VALUES(cipher_list);

-- ---- Optional: a dedicated per-tenant certificate, selected by TLS SNI ------
-- INSERT INTO tls_mgm (domain, type, match_sip_domain, method, verify_cert, require_cert)
--     VALUES ('acme_srv', 2, 'acme.teams.ucp.voiceland.dev', 'TLSv1_2+', 1, 1)
-- ON DUPLICATE KEY UPDATE method = VALUES(method);
