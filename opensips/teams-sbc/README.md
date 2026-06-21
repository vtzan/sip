# OpenSIPS 3.6 — Session Border Controller for Microsoft Teams

A multi-tenant Session Border Controller (SBC) for **Microsoft Teams Direct
Routing / Direct SIP trunking**, built on **OpenSIPS 3.6** with **rtpengine**
for media, packaged with **Docker Compose** (OpenSIPS + MariaDB + rtpengine +
rotation sidecar).

```
                    TLS :5560 (mutual)                 TCP :5560
                    SRTP (RTP/SAVP)                     RTP  (RTP/AVP)
   ┌───────────────┐   ◄────────────►   ┌───────────────────┐   ◄────────────►   ┌────────────────────────┐
   │ Microsoft     │   SIP signalling   │   OpenSIPS 3.6     │   SIP signalling   │  core                  │
   │ Teams         │◄══════════════════►│   + rtpengine      │◄══════════════════►│  eu.ucp.voiceland.dev  │
   │ Direct Routing│   media (rtpengine)│   (this SBC)       │   media (rtpengine)│  / .global  (2 IPs)    │
   └───────────────┘                    └───────────────────┘                    └────────────────────────┘
```

## Routing model

* **Teams → core**: every inbound call is relayed to the core FQDN
  `eu.ucp.voiceland.dev:5560/TCP` (dev) or `eu.ucp.voiceland.global:5560/TCP`
  (prod). The prod FQDN resolves to 2 IPs; tm fails over between them via DNS.
* **core → Teams**: the tenant is taken from the **From-URI host**, falling back
  to the **P-Asserted-Identity host**. That domain **must exist in the `tls_mgm`
  table**; the call is then sent to the Microsoft `pstnhub` proxies (with
  sip → sip2 → sip3 failover).
* **Trusted core source IPs** live in the `address` table and are refreshed from
  DNS (`ips.ucp.voiceland.global` / `eu.ucp.voiceland.dev`) **every 5 minutes**
  by the sidecar.
* **TLS is exposed on `5560` only** (Teams leg), mutual TLS. **All certificates
  and tenant identities are in the database** (`tls_mgm`) and rotated
  automatically before expiry.
* **rtpengine** bridges Teams **SRTP** (`RTP/SAVP`) ↔ core **RTP** (`RTP/AVP`).
* **All OpenSIPS module variables live in `local.m4`** — `opensips.m4` is a pure
  m4 template.

---

## Files

| Path                              | Purpose                                                       |
|-----------------------------------|---------------------------------------------------------------|
| `docker-compose.yml`              | mysql + opensips + rtpengine + rotation sidecar.              |
| `docker/`                         | Dockerfile, entrypoints, first-boot cert bootstrap, core-IP refresh. |
| `local.m4`                        | **All** site/module variables (edit this).                   |
| `opensips.m4`                     | OpenSIPS script template (do not edit for site values).      |
| `Makefile`                        | Builds `opensips.cfg`.                                        |
| `sql/01-schema.sql`               | `tls_mgm` + `address` tables (+ version rows).               |
| `sql/02-seed-example.sql`         | Base `teams_srv` / `teams_cli` TLS rows.                      |
| `scripts/create-tenant.sh`        | Provision a tenant (can send to / receive from Teams).       |
| `tls-rotation/`                   | DB cert management + automatic ACME rotation.                |
| `rtpengine/rtpengine.conf`        | Sample rtpengine config (compose uses CLI flags).            |
| `opensips.cfg`, `.env`, `tls-rotation/rotation.conf` | generated / secret — git-ignored.         |

---

## Quick start (Docker Compose)

```bash
cd opensips/teams-sbc
cp docker/.env.example .env            # DB password, MEDIA_IP, CORE_IPS_FQDN, ACME creds
cp tls-rotation/rotation.conf.example tls-rotation/rotation.conf
# edit local.m4: M_TEAMS_TLS_*_IP, M_CORE_*_IP, M_CORE_FQDN (dev vs prod)

docker compose up -d --build
docker compose logs -f opensips        # watch the bootstrap + start
```

On **first boot** the opensips container detects there is no certificate yet,
**generates a self-signed one** (covering the wildcard/base FQDNs) and loads it
into `tls_mgm` so OpenSIPS can open its TLS socket and start. The sidecar then
obtains real ACME certificates and keeps the core IP list current.

### Add a tenant

```bash
docker compose exec opensips \
  /etc/opensips/teams-sbc/scripts/create-tenant.sh acme.teams.ucp.voiceland.dev
```

This inserts the tenant into `tls_mgm` (so From/PAI validation passes and the
tenant's cert is served by SNI), installs a temporary self-signed cert, and
hot-reloads. The next ACME rotation issues a trusted certificate.

---

## Configure `local.m4`

| Variable                          | Meaning                                                    |
|-----------------------------------|------------------------------------------------------------|
| `M_TEAMS_TLS_LISTEN_IP` / `…_ADVERTISED_IP` | bind IP vs. public IP for the Teams TLS leg.    |
| `M_CORE_FQDN` / `M_CORE_PORT` / `M_CORE_TRANSPORT` | core destination (eu.ucp.voiceland.X:5560/tcp). |
| `M_CORE_LISTEN_IP` / `…_ADVERTISED_IP` / `M_CORE_SIP_PORT` | SBC core-facing socket.        |
| `M_CORE_GROUP`                    | `address` table group for trusted core IPs (default 1).    |
| `M_DB_URL` / `M_DB_MODULE`        | database connection (tls_mgm, permissions, sqlops).        |
| `M_MI_HTTP_IP` / `M_MI_HTTP_PORT` | MI HTTP endpoint used by the sidecar (127.0.0.1:8888).     |
| `M_RTPENGINE_SOCK`                | rtpengine ng control socket.                               |

The **core discovery FQDN** for the 5-minute refresh is `CORE_IPS_FQDN` in
`.env` (sidecar), not in `local.m4`.

---

## Database & certificate management

| Table     | Holds                                                              | Live reload     |
|-----------|-------------------------------------------------------------------|-----------------|
| `tls_mgm` | TLS domains + cert/key/CA (BLOB); also the **tenant registry**.    | `tls_mgm:reload`|
| `address` | Trusted core source IPs (group 1), refreshed from DNS every 5 min. | `address_reload`|

```bash
python3 tls-rotation/manage-tls.py check      # expiry of every certificate
python3 tls-rotation/manage-tls.py rotate     # renew anything within 30 days
```

See [`tls-rotation/README.md`](tls-rotation/README.md) for the rotation detail
and the standalone (non-Docker) systemd timer.

---

## Call flows

**Inbound (Teams → core)** — INVITE over TLS/5560 from a Microsoft subnet →
Contact/Record-Route branded with the tenant FQDN (R-URI host) on the Teams
side → `rtpengine_offer` SRTP→RTP → relayed to `M_CORE_DST`
(`eu.ucp.voiceland.X:5560/tcp`).

**Outbound (core → Teams)** — INVITE from a trusted core IP (`address` table) →
tenant = From host (else PAI host), verified in `tls_mgm` via `sqlops` →
E.164 normalised, From/PAI/Contact re-homed to the tenant FQDN →
`rtpengine_offer` RTP→SRTP → sent to `sip.pstnhub.microsoft.com` with
`sip2`/`sip3` failover.

**OPTIONS keep-alive** — answered `200 OK` with an FQDN `Contact` (Microsoft
rejects a bare-IP Contact with `403`).

---

## Security notes

* The trust boundary on the Teams side is **mutual TLS** on 5560 (the peer must
  present a certificate chaining to `tls_mgm.ca_list`), plus the Microsoft
  source-IP regex (`M_TEAMS_SRC_IP_REGEX`).
* Core-side INVITEs are accepted **only** from IPs in the `address` table
  (group 1), and the resolved tenant must exist in `tls_mgm`.
* `.env`, `rotation.conf` (DB password) and all private keys/certs are
  git-ignored; keys live in the DB.

---

## References
- [Plan Direct Routing](https://learn.microsoft.com/en-us/microsoftteams/direct-routing-plan)
- [Direct Routing SIP protocol](https://learn.microsoft.com/en-us/microsoftteams/direct-routing-protocols-sip)
- [Connect the SBC](https://learn.microsoft.com/en-us/microsoftteams/direct-routing-connect-the-sbc)
