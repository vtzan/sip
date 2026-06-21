m4_divert(-1)
m4_dnl ============================================================================
m4_dnl  local.m4 -- site-specific variables for the OpenSIPS 3.6 Microsoft Teams SBC
m4_dnl ----------------------------------------------------------------------------
m4_dnl  EVERY tunable for EVERY OpenSIPS module lives in this file.  opensips.m4 is
m4_dnl  a pure template and must NOT be edited for per-site values.  Rebuild with:
m4_dnl       make           (== m4 -P local.m4 opensips.m4 > opensips.cfg)
m4_dnl
m4_dnl  TLS certificates + tenant identities are managed in the DATABASE (tls_mgm).
m4_dnl  Trusted core source IPs live in the `address` table, refreshed from DNS
m4_dnl  every 5 minutes by the rotation sidecar.
m4_dnl ============================================================================

m4_dnl ---------------------------------------------------------------------------
m4_dnl  1. DEPLOYMENT
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_DEPLOY_ENV',       `dev')
m4_define(`M_SBC_CONTACT_USER', `sbc')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  2. TEAMS-FACING LEG  (TLS only, port 5560 -- the ONLY TLS listener)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_TEAMS_TLS_LISTEN_IP',     `10.0.0.10')
m4_define(`M_TEAMS_TLS_ADVERTISED_IP', `203.0.113.10')
m4_define(`M_TEAMS_TLS_PORT',          `5560')
m4_define(`M_TEAMS_FORCE_SOCKET',   `tls:M_TEAMS_TLS_LISTEN_IP:M_TEAMS_TLS_PORT')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  3. CORE-FACING LEG  (eu.ucp.voiceland.{dev,global} : 5560 / TCP)
m4_dnl ---------------------------------------------------------------------------
m4_dnl  DEV  core FQDN : eu.ucp.voiceland.dev
m4_dnl  PROD core FQDN : eu.ucp.voiceland.global  (resolves to 2 IPs; tm DNS-fails
m4_dnl                   over between them automatically)
m4_define(`M_CORE_FQDN',      `eu.ucp.voiceland.dev')
m4_dnl  --- PRODUCTION: m4_define(`M_CORE_FQDN', `eu.ucp.voiceland.global') ---
m4_define(`M_CORE_PORT',      `5560')
m4_define(`M_CORE_TRANSPORT', `tcp')
m4_define(`M_CORE_DST', `sip:M_CORE_FQDN:M_CORE_PORT;transport=M_CORE_TRANSPORT')

m4_dnl  SBC core-facing socket (where the core sends to / the SBC sends from).
m4_dnl  The DESTINATION to the core is M_CORE_PORT (5560), but the SBC's own
m4_dnl  core-facing LISTEN port must differ from the Teams TLS 5560 when both are
m4_dnl  on the same host IP (you cannot bind tls and tcp on the same ip:port).
m4_dnl  Use a separate core IP if you want a symmetric :5560 listener instead.
m4_define(`M_CORE_LISTEN_IP',     `10.0.0.10')
m4_define(`M_CORE_ADVERTISED_IP', `10.0.0.10')
m4_define(`M_CORE_SIP_PORT',      `5060')
m4_define(`M_CORE_FORCE_SOCKET', `tcp:M_CORE_LISTEN_IP:M_CORE_SIP_PORT')

m4_dnl  permissions `address` table group holding the trusted core node IPs.
m4_define(`M_CORE_GROUP', `1')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  4. DATABASE (shared by tls_mgm, permissions, sqlops)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_DB_MODULE', `db_mysql.so')
m4_define(`M_DB_URL',    `mysql://opensips:opensipsrw@127.0.0.1/opensips')
m4_define(`M_TLS_DB_TABLE', `tls_mgm')
m4_define(`M_ADDRESS_TABLE', `address')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  5. MANAGEMENT INTERFACE
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_FIFO_PATH',    `/var/run/opensips/opensips_fifo')
m4_define(`M_MI_HTTP_IP',   `127.0.0.1')
m4_define(`M_MI_HTTP_PORT', `8888')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  6. MICROSOFT TEAMS SIP PROXIES & SOURCE NETWORKS
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_TEAMS_PROXY_1', `sip:sip.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_PROXY_2', `sip:sip2.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_PROXY_3', `sip:sip3.pstnhub.microsoft.com:5061;transport=tls')

m4_dnl  Microsoft SIP signalling source subnets 52.112.0.0/14 and 52.122.0.0/14.
m4_define(`M_TEAMS_SRC_IP_REGEX', `^52\.(11[2-5]|12[0-3])\.')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  7. RTPENGINE (media relay + RTP<->SRTP transcoding)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_RTPENGINE_SOCK', `udp:127.0.0.1:2223')
m4_define(`M_RTPENGINE_FLAGS_TO_TEAMS',
          `RTP/SAVP replace-origin replace-session-connection ICE=remove rtcp-mux-offer')
m4_define(`M_RTPENGINE_FLAGS_TO_CORE',
          `RTP/AVP replace-origin replace-session-connection ICE=remove rtcp-mux-demux')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  8. CORE / MODULE TUNING
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_LOG_LEVEL',     `3')
m4_define(`M_UDP_WORKERS',   `4')
m4_define(`M_TCP_WORKERS',   `4')
m4_define(`M_MODULES_PATH',  `/usr/lib/x86_64-linux-gnu/opensips/modules/')

m4_divert(0)m4_dnl
