# OpenSIPS 3.6 — Session Border Controller for Microsoft Teams

A multi-tenant Session Border Controller (SBC) for **Microsoft Teams Direct
Routing / Direct SIP trunking**, built on **OpenSIPS 3.6** with **rtpengine**
for media.

```
                         TLS :5560 (mutual)              UDP/TCP :5060
                         SRTP (RTP/SAVP)                 RTP  (RTP/AVP)
   ┌───────────────┐   ◄──────────────────►   ┌───────────────────┐   ◄──────────────►   ┌──────────────┐
   │ Microsoft     │      SIP signalling      │   OpenSIPS 3.6     │     SIP signalling   │  Carrier /   │
   │ Teams         │◄════════════════════════►│   (this SBC)       │◄════════════════════►│  SIP core    │
   │ Direct Routing│      media (rtpengine)   │   + rtpengine      │     media (rtpengine)│  / trunk     │
   └───────────────┘                          └───────────────────┘                      └──────────────┘
```

* **TLS is exposed on port `5560` only** (the Teams leg). No other TLS port is opened.
* **Mutual TLS** with Microsoft (`verify_cert` + `require_cert`).
* **All TLS certificates are managed in the database** (`tls_mgm` table) and
  **rotated automatically** before expiry — see [`tls-rotation/`](tls-rotation/).
* **rtpengine** bridges Teams **SRTP** (`RTP/SAVP`, SDES) ↔ carrier **RTP** (`RTP/AVP`).
* **Full multi-tenancy** — the allowed tenant domains are the DB `domain` table:
  * `‹tenant›.teams.ucp.voiceland.dev` (development)
  * `‹tenant›.teams.ucp.voiceland.global` (production)
* Inbound (Teams → carrier) **and** outbound (carrier → Teams) calling.
* **All module variables live in `local.m4`** — `opensips.m4` is a pure template.

---

## Files

| File                       | Purpose                                                            |
|----------------------------|-------------------------------------------------------------------|
| `local.m4`                 | **All** site/module variables (edit this).                        |
| `opensips.m4`              | OpenSIPS script template (do not edit for site values).           |
| `Makefile`                 | Builds `opensips.cfg` and validates it.                           |
| `sql/01-schema.sql`        | `domain` + `tls_mgm` table schema (+ version rows).               |
| `sql/02-seed-example.sql`  | Example tenant domains and TLS rows.                              |
| `tls-rotation/`            | DB cert management + automatic ACME rotation (systemd timer).     |
| `rtpengine/rtpengine.conf` | Sample rtpengine config (media plane).                            |
| `tls/README.md`            | CA-bundle bootstrap notes (certs themselves live in the DB).      |
| `opensips.cfg`             | **Generated** runtime config (git-ignored).                       |

---

## How the build works

The runtime config is generated with `m4`:

```
m4 -P local.m4 opensips.m4 > opensips.cfg
```

* `-P` prefixes all m4 builtins with `m4_`, so they never collide with the
  OpenSIPS scripting language.
* Every variable is a macro named `M_*` defined in `local.m4`.

```bash
make            # generate opensips.cfg
make check      # generate, then validate with `opensips -C` (needs opensips installed)
make install    # install to /etc/opensips/opensips.cfg
```

---

## Prerequisites

1. **OpenSIPS 3.6** with these modules: `db_mysql` (or `db_postgres`),
   `proto_udp`, `proto_tcp`, `proto_tls`, `tls_mgm`, `sl`, `tm`, `signaling`,
   `rr`, `maxfwd`, `sipmsgops`, `uac`, `domain`, `dialog`, `rtpengine`,
   `htable`, `mi_fifo`.
2. **MySQL/MariaDB** (or PostgreSQL) reachable at `M_DB_URL`, with the schema
   from [`sql/01-schema.sql`](sql/01-schema.sql) applied.
3. **rtpengine** running and reachable on the control socket configured in
   `M_RTPENGINE_SOCK` (default `udp:127.0.0.1:2223`).
4. A **public-CA TLS certificate** covering your tenant FQDNs (a wildcard works
   best), issued/rotated into the DB by [`tls-rotation/`](tls-rotation/).
5. **DNS**: every tenant FQDN (`tenant.teams.ucp.voiceland.dev`/`.global`) and
   the base OPTIONS FQDN must resolve (publicly) to the SBC public IP
   (`M_TEAMS_TLS_ADVERTISED_IP`).
6. **Firewall**: allow inbound TLS `5560/tcp` and rtpengine's media UDP range
   from the Microsoft signalling/media subnets (`52.112.0.0/14`,
   `52.120.0.0/14`, `52.122.0.0/14`).
7. **Microsoft 365 / Teams admin**: each tenant FQDN registered as a PSTN
   gateway (`New-CsOnlinePSTNGateway -Fqdn tenant.teams.ucp.voiceland.dev
   -SipSignalingPort 5560 -Enabled $true`) with the matching voice route /
   PSTN usage / voice-routing policy.

---

## Configure `local.m4`

Edit the variables grouped by section. The most important ones:

| Variable                       | Meaning                                                       |
|--------------------------------|---------------------------------------------------------------|
| `M_DEPLOY_ENV`                 | `dev` or `prod` (selects the active base domain).             |
| `M_TEAMS_TENANT_BASE_DOMAIN`   | `teams.ucp.voiceland.dev` (dev) / `…global` (prod).           |
| `M_TEAMS_TLS_LISTEN_IP` / `…_ADVERTISED_IP` | bind IP vs. public IP for the Teams leg.         |
| `M_CARRIER_LISTEN_IP` / `…_ADVERTISED_IP` / `…_SIP_PORT` | the carrier/core leg.            |
| `M_DB_URL` / `M_DB_MODULE`     | database connection (shared by `tls_mgm` + `domain`).         |
| `M_RTPENGINE_SOCK`             | rtpengine ng control socket.                                  |
| `M_CARRIER_SRC_PROVISIONING`   | the carrier-IP → tenant FQDN map (outbound branding).         |

### Tenant provisioning

A tenant is provisioned in two places:

1. **Database `domain` table** (the allowed-domains list). The `attrs` column
   holds the inbound carrier trunk SIP URI — this is where calls **from Teams**
   for that tenant are sent. See [`sql/02-seed-example.sql`](sql/02-seed-example.sql):

   ```sql
   INSERT INTO domain (domain, attrs, accept_subdomain, last_modified) VALUES
     ('acme.teams.ucp.voiceland.dev', 'sip:198.51.100.10:5060', 0, NOW());
   ```
   Reload live with `opensips-cli -x mi domain:reload`.

2. **`M_CARRIER_SRC_PROVISIONING` in `local.m4`** — the reverse map (carrier
   source IP → tenant FQDN) used to brand **outbound** calls to Teams:

   ```m4
   $sht(carrier_src=>198.51.100.10) = "acme.M_TEAMS_TENANT_BASE_DOMAIN";
   ```

The SBC validates every tenant domain against the `domain` table at call time
(`is_uri_host_local` / `is_domain_local`).

---

## Call flows

### Inbound — Teams → carrier
1. INVITE arrives over TLS/5560 from a Microsoft subnet (`IS_FROM_TEAMS`).
2. Tenant = host of the Request-URI; validated against the DB `domain` table
   with `is_uri_host_local()`, which also returns the carrier trunk (`attrs`).
3. `Contact` rewritten to the SBC carrier address; **double Record-Route**
   places the **tenant FQDN** on the Teams side and the SBC IP on the carrier side.
4. `rtpengine_offer` converts the Teams **SRTP** offer to carrier **RTP**.
5. Relayed to the tenant's carrier trunk. The 200 OK is converted back to SRTP
   and its `Contact` re-branded with the tenant FQDN (`MANAGE_REPLY`).

### Outbound — carrier → Teams
1. INVITE arrives from a provisioned carrier IP (`IS_FROM_CARRIER`) → tenant
   resolved from `carrier_src`.
2. Number normalised to E.164; `From`/`P-Asserted-Identity` re-homed to the
   tenant FQDN; **`Contact` set to the tenant FQDN** (this is how Microsoft maps
   the call to the right trunk).
3. `rtpengine_offer` converts carrier **RTP** to Teams **SRTP**.
4. Sent to `sip.pstnhub.microsoft.com` (TLS); `MANAGE_FAILURE` fails over to
   `sip2`/`sip3` on timeout/5xx.

### OPTIONS keep-alive
Microsoft polls the trunk with `OPTIONS`; the SBC answers `200 OK` with an
**FQDN** `Contact` (`TEAMS_OPTIONS_KEEPALIVE`). Microsoft requires the FQDN —
a bare-IP Contact is rejected with `403`.

---

## Why the per-tenant FQDN matters

Microsoft attributes an inbound (SBC→Teams) call to a tenant **by the FQDN in
the `Contact`/`Record-Route`**, not by IP. All tenant FQDNs resolve to the same
SBC IP and are covered by one wildcard certificate, but each call must carry its
**own** tenant subdomain. That is exactly what `record_route_preset(...)` and
the `Contact` rewrites in `opensips.m4` do. Using a single shared FQDN would
collapse every tenant onto one trunk.

---

## Database & certificate management

TLS certificates and the allowed-domains list are **in the database**:

| Table     | Holds                                                              | Live reload |
|-----------|-------------------------------------------------------------------|-------------|
| `tls_mgm` | Server/client TLS domains + certificate/key/CA chains (BLOB).     | `tls_mgm:reload` |
| `domain`  | Allowed tenant FQDNs; `attrs` = inbound carrier trunk URI.        | `domain:reload`  |

```bash
mysql opensips < sql/01-schema.sql            # tables + version rows
mysql opensips < sql/02-seed-example.sql      # your tenants + TLS rows
opensips-cli -x mi domain:reload
```

**Automatic certificate rotation** (issue/renew before expiry, write to DB,
hot-reload) is handled by [`tls-rotation/`](tls-rotation/) via a daily systemd
timer:

```bash
python3 tls-rotation/manage-tls.py check      # show expiry of every cert
python3 tls-rotation/manage-tls.py rotate     # renew anything within 30 days
```

See [`tls-rotation/README.md`](tls-rotation/README.md) for the full bootstrap
and the systemd timer install.

---

## Validate & run

```bash
make check                      # opensips -C -f opensips.cfg
opensips -f /etc/opensips/opensips.cfg   # or via systemd
```

Health checks:

```bash
opensips-cli -x mi ps                       # processes
opensips-cli -x mi get_statistics dialog:   # active dialogs
opensips-cli -x mi tls_mgm:reload           # reload certs from DB
opensips-cli -x mi domain:reload            # reload allowed domains from DB
```

---

## Security notes

* The primary trust boundary is **mutual TLS** on 5560 — only a peer presenting
  a certificate that chains to the `tls_mgm.ca_list` bundle can connect. The
  Microsoft source-IP regex (`M_TEAMS_SRC_IP_REGEX`) is defence-in-depth; keep
  it current with Microsoft's published ranges.
* Carrier-side INVITEs are accepted **only** from IPs present in `carrier_src`,
  and the resolved tenant must exist in the `domain` table.
* Private keys live in the DB (and never in git); `rotation.conf` (DB password)
  is git-ignored.

---

## Troubleshooting

| Symptom                          | Likely cause                                                        |
|----------------------------------|---------------------------------------------------------------------|
| Teams marks trunk **inactive**   | OPTIONS not answered `200`, or Contact host is an IP not an FQDN.    |
| `403` from Teams on outbound     | `Contact`/`Record-Route` host not the tenant FQDN, or cert SAN mismatch. |
| TLS handshake fails              | Cert not from a Microsoft-supported public CA, or `ca_list` can't verify Microsoft's cert. |
| One-way / no audio               | rtpengine media ports not open to `52.112/14`, `52.120/14`; check `interface` in `rtpengine.conf`. |
| `488 Not Acceptable Here`        | SRTP/codec mismatch — review `M_RTPENGINE_FLAGS_TO_TEAMS`.           |
| INVITE `404 Tenant Not Provisioned` | Tenant FQDN missing from `M_TENANT_PROVISIONING`.                |

---

## References
- [Plan Direct Routing](https://learn.microsoft.com/en-us/microsoftteams/direct-routing-plan)
- [Direct Routing SIP protocol](https://learn.microsoft.com/en-us/microsoftteams/direct-routing-protocols-sip)
- [Connect the SBC](https://learn.microsoft.com/en-us/microsoftteams/direct-routing-connect-the-sbc)
- [OpenSIPS as MS Teams SBC](https://blog.opensips.org/2019/09/16/opensips-as-ms-teams-sbc/)
