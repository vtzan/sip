m4_divert(-1)
m4_dnl ============================================================================
m4_dnl  local.m4 -- site-specific variables for the OpenSIPS 3.6 Microsoft Teams SBC
m4_dnl ----------------------------------------------------------------------------
m4_dnl  EVERY tunable for EVERY OpenSIPS module lives in this file.  opensips.m4 is
m4_dnl  a pure template and must NOT be edited for per-site values.  After changing
m4_dnl  anything here, regenerate the runtime config with:   make
m4_dnl
m4_dnl  Build command:   m4 -P local.m4 opensips.m4 > opensips.cfg
m4_dnl  (the -P flag prefixes m4 builtins with m4_ so they never collide with the
m4_dnl   OpenSIPS script language)
m4_dnl ============================================================================

m4_dnl ---------------------------------------------------------------------------
m4_dnl  1. DEPLOYMENT / DOMAINS
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Multi-tenant base domain. Each Teams customer gets a sub-domain:
m4_dnl      <tenant>.teams.ucp.voiceland.dev      (development)
m4_dnl      <tenant>.teams.ucp.voiceland.global   (production)
m4_dnl  Set the ACTIVE base domain for THIS instance below. The tenant validation
m4_dnl  regex (M_TENANT_HOST_REGEX) accepts BOTH base domains so a single binary
m4_dnl  may serve dev and prod tenants if required.
m4_define(`M_DEPLOY_ENV',              `dev')
m4_define(`M_TEAMS_TENANT_BASE_DOMAIN', `teams.ucp.voiceland.dev')
m4_dnl  --- PRODUCTION: comment the two lines above and uncomment the two below ---
m4_dnl m4_define(`M_DEPLOY_ENV',              `prod')
m4_dnl m4_define(`M_TEAMS_TENANT_BASE_DOMAIN', `teams.ucp.voiceland.global')

m4_dnl  FQDN used as Contact in the OPTIONS keep-alives WE answer (base domain,
m4_dnl  must be present in the TLS certificate SAN list).
m4_define(`M_SBC_OPTIONS_FQDN',        `sbc.teams.ucp.voiceland.dev')

m4_dnl  Accepts <label>.teams.ucp.voiceland.dev OR .global  (single DNS label tenant)
m4_define(`M_TENANT_HOST_REGEX',
          `^[a-z0-9]([a-z0-9-]*[a-z0-9])?\.teams\.ucp\.voiceland\.(dev|global)$')

m4_dnl  User-part placed in every Contact header the SBC generates.
m4_define(`M_SBC_CONTACT_USER',        `sbc')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  2. NETWORK / SOCKETS
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Teams-facing leg : TLS only, port 5560 (the ONLY TLS listener on the box).
m4_dnl  *_LISTEN_IP    = address OpenSIPS binds to (private if behind 1:1 NAT)
m4_dnl  *_ADVERTISED_IP = public address put into Via / Contact / Record-Route
m4_define(`M_TEAMS_TLS_LISTEN_IP',     `10.0.0.10')
m4_define(`M_TEAMS_TLS_ADVERTISED_IP', `203.0.113.10')
m4_define(`M_TEAMS_TLS_PORT',          `5560')

m4_dnl  Carrier / trunk-facing leg (towards your internal SIP core or upstream
m4_dnl  carrier). Non-TLS by requirement (TLS lives on 5560 only).
m4_define(`M_CARRIER_LISTEN_IP',       `10.0.0.10')
m4_define(`M_CARRIER_ADVERTISED_IP',   `10.0.0.10')
m4_define(`M_CARRIER_SIP_PORT',        `5060')

m4_dnl  Pre-computed socket selectors used by $fs (force-send-socket).
m4_define(`M_TEAMS_FORCE_SOCKET',   `tls:M_TEAMS_TLS_LISTEN_IP:M_TEAMS_TLS_PORT')
m4_define(`M_CARRIER_FORCE_SOCKET', `udp:M_CARRIER_LISTEN_IP:M_CARRIER_SIP_PORT')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  3. TLS (tls_mgm) -- mutual TLS with Microsoft
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Certificate MUST cover the tenant FQDNs, e.g. a wildcard
m4_dnl  *.teams.ucp.voiceland.dev (+ *.teams.ucp.voiceland.global for prod) and the
m4_dnl  base SBC FQDN. ca_list MUST contain the public root chain that signs the
m4_dnl  Microsoft SIP proxy certificate (DigiCert / Baltimore) so require_cert works.
m4_define(`M_TLS_CERT',    `/etc/opensips/tls/teams/wildcard.crt.pem')
m4_define(`M_TLS_KEY',     `/etc/opensips/tls/teams/wildcard.key.pem')
m4_define(`M_TLS_CA',      `/etc/opensips/tls/teams/ca-bundle.pem')
m4_define(`M_TLS_METHOD',  `TLSv1_2+')
m4_define(`M_TLS_CIPHERS', `HIGH:!aNULL:!eNULL:!MD5:!RC4:!3DES:!EXPORT')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  4. MICROSOFT TEAMS SIP PROXIES & SOURCE NETWORKS
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Direct Routing signalling proxies (try primary first, then fail over).
m4_define(`M_TEAMS_PROXY_1', `sip:sip.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_PROXY_2', `sip:sip2.pstnhub.microsoft.com:5061;transport=tls')
m4_define(`M_TEAMS_PROXY_3', `sip:sip3.pstnhub.microsoft.com:5061;transport=tls')

m4_dnl  Microsoft SIP signalling source subnets 52.112.0.0/14 and 52.122.0.0/14
m4_dnl  (== 52.112-115.x and 52.120-123.x). Used as a defence-in-depth source check
m4_dnl  on top of mutual TLS. Adjust if Microsoft publishes new ranges.
m4_define(`M_TEAMS_SRC_IP_REGEX', `^52\.(11[2-5]|12[0-3])\.')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  5. RTPENGINE (media relay + RTP<->SRTP transcoding)
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_RTPENGINE_SOCK', `udp:127.0.0.1:2223')

m4_dnl  Flags applied to the SDP that LEAVES the SBC toward Microsoft Teams:
m4_dnl  force SRTP (RTP/SAVP), strip ICE (non-media-bypass), offer rtcp-mux,
m4_dnl  rewrite c=/o= lines to the SBC public media address.
m4_define(`M_RTPENGINE_FLAGS_TO_TEAMS',
          `RTP/SAVP replace-origin replace-session-connection ICE=remove rtcp-mux-offer')

m4_dnl  Flags applied to the SDP that LEAVES the SBC toward the carrier/core:
m4_dnl  plain RTP/AVP, strip ICE, de-mux rtcp.
m4_define(`M_RTPENGINE_FLAGS_TO_CARRIER',
          `RTP/AVP replace-origin replace-session-connection ICE=remove rtcp-mux-demux')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  6. CORE / MODULE TUNING
m4_dnl ---------------------------------------------------------------------------
m4_define(`M_LOG_LEVEL',     `3')
m4_define(`M_UDP_WORKERS',   `4')
m4_define(`M_TCP_WORKERS',   `4')
m4_define(`M_MODULES_PATH',  `/usr/lib/x86_64-linux-gnu/opensips/modules/')
m4_define(`M_FIFO_PATH',     `/var/run/opensips/opensips_fifo')
m4_define(`M_HTABLE_SIZE',   `8')

m4_dnl ---------------------------------------------------------------------------
m4_dnl  7. TENANT PROVISIONING
m4_dnl ---------------------------------------------------------------------------
m4_dnl  Two in-memory maps, loaded once at start-up:
m4_dnl    tenant_trunk : <tenant-fqdn>      -> carrier $du (where Teams calls go)
m4_dnl    carrier_src  : <carrier-source-ip> -> <tenant-fqdn> (who is calling Teams)
m4_dnl  Add one stanza per tenant. The base domain is appended automatically.
m4_define(`M_TENANT_PROVISIONING', `m4_dnl
	$sht(tenant_trunk=>acme.M_TEAMS_TENANT_BASE_DOMAIN)    = "sip:198.51.100.10:5060;transport=udp";
	$sht(carrier_src=>198.51.100.10)                       = "acme.M_TEAMS_TENANT_BASE_DOMAIN";

	$sht(tenant_trunk=>contoso.M_TEAMS_TENANT_BASE_DOMAIN) = "sip:198.51.100.20:5060;transport=udp";
	$sht(carrier_src=>198.51.100.20)                       = "contoso.M_TEAMS_TENANT_BASE_DOMAIN";
')

m4_divert(0)m4_dnl
