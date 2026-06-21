m4_divert(-1)
m4_dnl ============================================================================
m4_dnl  local.m4 -- variables for the OpenSIPS 3.6 Microsoft Teams SBC
m4_dnl ----------------------------------------------------------------------------
m4_dnl  Every value is read from an ENVIRONMENT VARIABLE (with a sensible default)
m4_dnl  via the M_ENV(NAME, DEFAULT) helper, so a single image serves any instance
m4_dnl  / environment. In Docker the values come from the selected env file
m4_dnl  (.env.sbcX.dev / .env.sbcX.prod), injected into the container. Outside
m4_dnl  Docker, export the vars or just rely on the defaults below.
m4_dnl
m4_dnl  Rebuild:   make    (== m4 -P local.m4 opensips.m4 > opensips.cfg)
m4_dnl ============================================================================

m4_dnl  M_ENV(VARNAME, DEFAULT) -> value of $VARNAME, or DEFAULT when unset/empty.
m4_define(`M_ENV', `m4_esyscmd(`printf %s "${'$1`:-'$2`}"')')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  1. DEPLOYMENT
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_DEPLOY_ENV',       `M_ENV(`DEPLOY_ENV', `dev')')
m4_define(`M_SBC_INSTANCE',     `M_ENV(`SBC_INSTANCE', `sbc1')')
m4_define(`M_SBC_CONTACT_USER', `M_ENV(`SBC_CONTACT_USER', `sbc')')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  2. TEAMS-FACING LEG  (TLS only, port 5560 -- the ONLY TLS listener)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_TEAMS_TLS_LISTEN_IP',     `M_ENV(`TEAMS_TLS_LISTEN_IP', `10.0.0.10')')
m4_define(`M_TEAMS_TLS_ADVERTISED_IP', `M_ENV(`TEAMS_TLS_ADVERTISED_IP', `203.0.113.10')')
m4_define(`M_TEAMS_TLS_PORT',          `M_ENV(`TEAMS_TLS_PORT', `5560')')
m4_define(`M_TEAMS_FORCE_SOCKET',   `tls:M_TEAMS_TLS_LISTEN_IP:M_TEAMS_TLS_PORT')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  3. CORE-FACING LEG  (eu.ucp.voiceland.{dev,global} : 5560 / TCP)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_CORE_FQDN',      `M_ENV(`CORE_FQDN', `eu.ucp.voiceland.dev')')
m4_define(`M_CORE_PORT',      `M_ENV(`CORE_PORT', `5560')')
m4_define(`M_CORE_TRANSPORT', `M_ENV(`CORE_TRANSPORT', `tcp')')
m4_define(`M_CORE_DST', `sip:M_CORE_FQDN:M_CORE_PORT;transport=M_CORE_TRANSPORT')

m4_dnl  SBC core-facing socket. The DESTINATION to the core is M_CORE_PORT (5560),
m4_dnl  but the SBC's own LISTEN port must differ from the Teams TLS 5560 when both
m4_dnl  are on the same host IP (cannot bind tls and tcp on the same ip:port).
m4_define(`M_CORE_LISTEN_IP',     `M_ENV(`CORE_LISTEN_IP', `10.0.0.10')')
m4_define(`M_CORE_ADVERTISED_IP', `M_ENV(`CORE_ADVERTISED_IP', `10.0.0.10')')
m4_define(`M_CORE_SIP_PORT',      `M_ENV(`CORE_SIP_PORT', `5060')')
m4_define(`M_CORE_FORCE_SOCKET', `M_CORE_TRANSPORT:M_CORE_LISTEN_IP:M_CORE_SIP_PORT')

m4_dnl  permissions `address` table group holding the trusted core node IPs.
m4_define(`M_CORE_GROUP', `M_ENV(`CORE_GROUP', `1')')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  4. DATABASE (shared by tls_mgm, permissions, sqlops)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_DB_MODULE', `M_ENV(`DB_MODULE', `db_mysql.so')')
m4_define(`M_DB_URL',
  `mysql://M_ENV(`DB_USER', `opensips'):M_ENV(`DB_PASS', `opensipsrw')@M_ENV(`DB_HOST', `127.0.0.1'):M_ENV(`DB_PORT', `3306')/M_ENV(`DB_NAME', `opensips')')
m4_define(`M_TLS_DB_TABLE', `M_ENV(`TLS_DB_TABLE', `tls_mgm')')
m4_define(`M_ADDRESS_TABLE', `M_ENV(`ADDRESS_TABLE', `address')')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  5. MANAGEMENT INTERFACE
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_FIFO_PATH',    `M_ENV(`FIFO_PATH', `/var/run/opensips/opensips_fifo')')
m4_define(`M_MI_HTTP_IP',   `M_ENV(`MI_HTTP_IP', `127.0.0.1')')
m4_define(`M_MI_HTTP_PORT', `M_ENV(`MI_HTTP_PORT', `8888')')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  6. MICROSOFT TEAMS SIP PROXIES & SOURCE NETWORKS  (static)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_TEAMS_PROXY_1', `sip:sip.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_PROXY_2', `sip:sip2.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_PROXY_3', `sip:sip3.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_SRC_IP_REGEX', `^52\.(11[2-5]|12[0-3])\.')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  7. RTPENGINE (media relay + RTP<->SRTP transcoding)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_RTPENGINE_SOCK', `M_ENV(`RTPENGINE_SOCK', `udp:127.0.0.1:2223')')
m4_define(`M_RTPENGINE_FLAGS_TO_TEAMS',
          `RTP/SAVP replace-origin replace-session-connection ICE=remove rtcp-mux-offer')
m4_define(`M_RTPENGINE_FLAGS_TO_CORE',
          `RTP/AVP replace-origin replace-session-connection ICE=remove rtcp-mux-demux')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  8. CORE / MODULE TUNING
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_LOG_LEVEL',     `M_ENV(`LOG_LEVEL', `3')')
m4_define(`M_UDP_WORKERS',   `M_ENV(`UDP_WORKERS', `4')')
m4_define(`M_TCP_WORKERS',   `M_ENV(`TCP_WORKERS', `4')')
m4_define(`M_MODULES_PATH',  `M_ENV(`MODULES_PATH', `/usr/lib/x86_64-linux-gnu/opensips/modules/')')

m4_divert(0)m4_dnl
