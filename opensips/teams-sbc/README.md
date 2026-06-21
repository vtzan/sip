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
| `.env.sbc1.dev.example` / `.env.sbc1.prod.example` | per-instance/env templates.            |
| `scripts/sbc.sh`                  | run compose for a given instance+env.                        |
| `opensips.cfg`, `.env.*`, `tls-rotation/rotation.conf` | generated / secret — git-ignored.       |

---

## Quick start (Docker Compose)

Each SBC instance + environment has its own env file: `.env.sbc1.dev`,
`.env.sbc1.prod`, `.env.sbc2.dev`, … `local.m4` reads every value from the
environment, so the **same image serves any instance/env** — no per-instance
config edits.

```bash
cd opensips/teams-sbc
cp .env.sbc1.dev.example .env.sbc1.dev     # set IPs, FQDNs, DB password, ACME creds
cp tls-rotation/rotation.conf.example tls-rotation/rotation.conf

scripts/sbc.sh sbc1 dev up -d --build      # bring up the sbc1/dev instance
scripts/sbc.sh sbc1 dev logs -f opensips   # watch the bootstrap + start
```

`scripts/sbc.sh <instance> <dev|prod> <args…>` wraps
`docker compose --env-file .env.<instance>.<env> …`. Each env file sets
`COMPOSE_PROJECT_NAME` and `ENV_FILE`, so instances get unique containers/volumes
and the file is injected into the containers.

> Add more: `cp .env.sbc1.prod.example .env.sbc2.prod`, edit it
> (`COMPOSE_PROJECT_NAME`, `SBC_INSTANCE`, IPs/FQDNs), then
> `scripts/sbc.sh sbc2 prod up -d`. Co-locating instances on **one host**
> requires distinct `TEAMS_TLS_*_IP` / `CORE_*` / `MEDIA_IP` and distinct
> `DB_PORT` / `MI_HTTP_PORT`.

On **first boot** the opensips container detects there is no certificate yet,
**generates a self-signed one** (covering the wildcard/base FQDNs) and loads it
into `tls_mgm` so OpenSIPS can open its TLS socket and start. The sidecar then
obtains real ACME certificates and keeps the core IP list current.

### Add a tenant

```bash
scripts/sbc.sh sbc1 dev exec opensips \
  /etc/opensips/teams-sbc/scripts/create-tenant.sh acme.teams.ucp.voiceland.dev
```

This inserts the tenant into `tls_mgm` (so From/PAI validation passes and the
tenant's cert is served by SNI), installs a temporary self-signed cert, and
hot-reloads. The next ACME rotation issues a trusted certificate.

---

## Configuration (environment variables)

`local.m4` reads every value via `M_ENV(NAME, DEFAULT)` (m4 `esyscmd`), so all
configuration is environment-driven — set in the instance env file
(`.env.sbcX.dev` / `.env.sbcX.prod`) for Docker, or exported for a bare
`make`/standalone build. The full list with defaults is in
`.env.sbc1.dev.example`. Key ones:

| Env var                           | Meaning                                                    |
|-----------------------------------|------------------------------------------------------------|
| `TEAMS_TLS_LISTEN_IP` / `TEAMS_TLS_ADVERTISED_IP` | bind vs. public IP for the Teams TLS leg.  |
| `CORE_FQDN` / `CORE_PORT` / `CORE_TRANSPORT` | core destination (eu.ucp.voiceland.X:5560/tcp).  |
| `CORE_LISTEN_IP` / `CORE_ADVERTISED_IP` / `CORE_SIP_PORT` | SBC core-facing socket.         |
| `CORE_IPS_FQDN`                   | DNS name resolved every 5 min for the trusted core IPs.    |
| `DB_HOST/PORT/USER/PASS/NAME`     | database (also `DB_PORT` = host-published MariaDB port).   |
| `MI_HTTP_IP` / `MI_HTTP_PORT` / `MI_URL` | MI HTTP endpoint (sidecar reload).                  |
| `MEDIA_IP` / `RTP_PORT_MIN/MAX`   | rtpengine media address + port range.                      |
| `DEPLOY_ENV` / `SBC_INSTANCE`     | labels for logs / bootstrap.                               |

Outside Docker, any unset variable falls back to the default baked into
`local.m4`, so `make` still produces a working `opensips.cfg`.

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
