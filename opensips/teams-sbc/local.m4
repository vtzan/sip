m4_divert(-1)
m4_dnl ============================================================================
m4_dnl  local.m4 -- site-specific variables for the OpenSIPS 3.6 Microsoft Teams SBC
m4_dnl ----------------------------------------------------------------------------
m4_dnl  EVERY tunable for EVERY OpenSIPS module lives in this file.  opensips.m4 is
m4_dnl  a pure template and must NOT be edited for per-site values.  After changing
m4_dnl  anything here, regenerate the runtime config with:   make
m4_dnl
m4_dnl  Build command:   m4 -P local.m4 opensips.m4 > opensips.cfg
m4_dnl
m4_dnl  NOTE: TLS certificates and the allowed-domains list are now managed in the
m4_dnl  DATABASE (tls_mgm + domain tables), not in files. See sql/ and tls-rotation/.
m4_dnl ============================================================================

m4_dnl ---------------------------------------------------------------------------
m4_dnl  1. DEPLOYMENT / DOMAINS
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Multi-tenant base domain. Each Teams customer gets a sub-domain:
m4_dnl      <tenant>.teams.ucp.voiceland.dev      (development)
m4_dnl      <tenant>.teams.ucp.voiceland.global   (production)
m4_dnl  The authoritative allow-list is the DB `domain` table; this value is only
m4_dnl  informational / used by helper scripts.
m4_define(`M_DEPLOY_ENV',              `dev')
m4_define(`M_TEAMS_TENANT_BASE_DOMAIN', `teams.ucp.voiceland.dev')
m4_dnl  --- PRODUCTION: comment the two lines above and uncomment the two below ---
m4_dnl m4_define(`M_DEPLOY_ENV',              `prod')
m4_dnl m4_define(`M_TEAMS_TENANT_BASE_DOMAIN', `teams.ucp.voiceland.global')

m4_dnl  FQDN used as Contact in the OPTIONS keep-alives WE answer (base domain,
m4_dnl  must be present in the TLS certificate SAN list).
m4_define(`M_SBC_OPTIONS_FQDN',        `sbc.teams.ucp.voiceland.dev')

m4_dnl  User-part placed in every Contact header the SBC generates.
m4_define(`M_SBC_CONTACT_USER',        `sbc')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  2. NETWORK / SOCKETS
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Teams-facing leg : TLS only, port 5560 (the ONLY TLS listener on the box).
m4_define(`M_TEAMS_TLS_LISTEN_IP',     `10.0.0.10')
m4_define(`M_TEAMS_TLS_ADVERTISED_IP', `203.0.113.10')
m4_define(`M_TEAMS_TLS_PORT',          `5560')

m4_dnl  Carrier / trunk-facing leg (non-TLS by requirement: TLS lives on 5560 only).
m4_define(`M_CARRIER_LISTEN_IP',       `10.0.0.10')
m4_define(`M_CARRIER_ADVERTISED_IP',   `10.0.0.10')
m4_define(`M_CARRIER_SIP_PORT',        `5060')

m4_dnl  Pre-computed socket selectors used by $fs (force-send-socket).
m4_define(`M_TEAMS_FORCE_SOCKET',   `tls:M_TEAMS_TLS_LISTEN_IP:M_TEAMS_TLS_PORT')
m4_define(`M_CARRIER_FORCE_SOCKET', `udp:M_CARRIER_LISTEN_IP:M_CARRIER_SIP_PORT')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  3. DATABASE (shared by tls_mgm + domain)
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Backend module: db_mysql.so (MariaDB/MySQL) or db_postgres.so (PostgreSQL).
m4_define(`M_DB_MODULE', `db_mysql.so')
m4_define(`M_DB_URL',    `mysql://opensips:opensipsrw@127.0.0.1/opensips')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  4. TLS -- database-managed certificates (tls_mgm)
m4_dnl ---------------------------------------------------------------------------
m4_dnl  All server/client TLS domains, certs, keys and CA chains come from this
m4_dnl  table. Rotation is handled by tls-rotation/manage-tls.py + a systemd timer.
m4_define(`M_TLS_DB_TABLE', `tls_mgm')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  5. DOMAIN -- allowed tenant domains (domain table)
m4_dnl ---------------------------------------------------------------------------
m4_dnl  db_mode 1 = cache the table in memory; reload via MI `domain:reload`.
m4_define(`M_DOMAIN_TABLE',   `domain')
m4_define(`M_DOMAIN_DB_MODE', `1')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  6. MICROSOFT TEAMS SIP PROXIES & SOURCE NETWORKS
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_TEAMS_PROXY_1', `sip:sip.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_PROXY_2', `sip:sip2.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_PROXY_3', `sip:sip3.pstnhub.microsoft.com:5061;transport=tls')

m4_dnl  Microsoft SIP signalling source subnets 52.112.0.0/14 and 52.122.0.0/14
m4_dnl  (== 52.112-115.x and 52.120-123.x). Defence-in-depth on top of mutual TLS.
m4_define(`M_TEAMS_SRC_IP_REGEX', `^52\.(11[2-5]|12[0-3])\.')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  7. RTPENGINE (media relay + RTP<->SRTP transcoding)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_RTPENGINE_SOCK', `udp:127.0.0.1:2223')
m4_define(`M_RTPENGINE_FLAGS_TO_TEAMS',
          `RTP/SAVP replace-origin replace-session-connection ICE=remove rtcp-mux-offer')
m4_define(`M_RTPENGINE_FLAGS_TO_CARRIER',
          `RTP/AVP replace-origin replace-session-connection ICE=remove rtcp-mux-demux')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  8. CORE / MODULE TUNING
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_LOG_LEVEL',     `3')
m4_define(`M_UDP_WORKERS',   `4')
m4_define(`M_TCP_WORKERS',   `4')
m4_define(`M_MODULES_PATH',  `/usr/lib/x86_64-linux-gnu/opensips/modules/')
m4_define(`M_FIFO_PATH',     `/var/run/opensips/opensips_fifo')
m4_define(`M_HTABLE_SIZE',   `8')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  9. CARRIER SOURCE PROVISIONING
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Reverse map (carrier source IP -> tenant FQDN) used to brand OUTBOUND calls
m4_dnl  to Teams. Inbound trunk + allow-list live in the DB `domain` table; this is
m4_dnl  the only file-based map. Add one line per carrier-trunk source IP.
m4_define(`M_CARRIER_SRC_PROVISIONING', `m4_dnl
	$sht(carrier_src=>198.51.100.10) = "acme.M_TEAMS_TENANT_BASE_DOMAIN";
	$sht(carrier_src=>198.51.100.20) = "contoso.M_TEAMS_TENANT_BASE_DOMAIN";
')

m4_divert(0)m4_dnl
