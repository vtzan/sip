# Database TLS management & automatic rotation

All TLS certificates for the Teams SBC live in the OpenSIPS `tls_mgm` database
table (PEM stored as BLOBs). `manage-tls.py` issues/renews them via ACME, writes
them back to the DB, and hot-reloads OpenSIPS — no restart, no dropped calls.

```
ACME (lego, DNS-01) ──▶ manage-tls.py ──▶ tls_mgm table ──▶ opensips-cli -x mi tls_mgm:reload
        ▲                                                              │
        └───────────────── daily systemd timer ────────────────────────┘
```

## Install

```bash
sudo mkdir -p /opt/opensips-teams-sbc
sudo cp -r . /opt/opensips-teams-sbc/tls-rotation
cd /opt/opensips-teams-sbc/tls-rotation
pip3 install -r requirements.txt          # PyMySQL, cryptography
cp rotation.conf.example rotation.conf    # then edit DB password, ACME hook, SAN map
```

Install an ACME client for `acme-hook.sh` (default is [`lego`](https://go-acme.github.io/lego/)),
and set your DNS-01 provider credentials (e.g. `CLOUDFLARE_DNS_API_TOKEN`) in the
environment / systemd unit.

## One-time bootstrap

```bash
# 1. schema + seed (see ../sql)
mysql opensips < ../sql/01-schema.sql
mysql opensips < ../sql/02-seed-example.sql

# 2. trust store for verifying Microsoft's certificate (mutual TLS)
python3 manage-tls.py set-ca --ca /etc/ssl/certs/ca-certificates.crt

# 3. issue the initial certificates and load them into the DB
python3 manage-tls.py rotate --force

# 4. verify, then (re)start OpenSIPS
python3 manage-tls.py check
```

> If you already hold certificates, skip ACME and import them directly:
> `python3 manage-tls.py load --domain teams_srv --cert fullchain.pem --key privkey.pem`

## Automatic rotation

```bash
sudo cp opensips-cert-rotation.service opensips-cert-rotation.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now opensips-cert-rotation.timer
systemctl list-timers opensips-cert-rotation.timer
```

The timer runs `manage-tls.py rotate` daily. Each run renews **every** managed
certificate whose leaf expires within `renew_threshold_days` (default 30),
covering all tenants — whether they share a wildcard cert or use a dedicated
per-tenant cert (`tls_mgm.match_sip_domain`). Changed rows trigger a single
`tls_mgm:reload`.

## Commands

| Command | Purpose |
|---------|---------|
| `manage-tls.py check` | List every cert with expiry date and `OK`/`RENEW`/`EXPIRED`. |
| `manage-tls.py set-ca --ca FILE [--domain ID]` | Install the peer-verification CA bundle. |
| `manage-tls.py load --domain ID --cert F --key F` | Import an existing cert/key into a row. |
| `manage-tls.py rotate [--force] [--dry-run]` | Renew expiring certs via ACME and reload. |

## How a certificate maps to SANs

For each `tls_mgm` row, `rotate` decides what to request:
1. If the row's `domain` id appears in the `[map]` section of `rotation.conf`,
   that SAN list is used (wildcards → one cert for all tenants).
2. Otherwise, if the row sets `match_sip_domain`, that single FQDN is requested
   (per-tenant certificate selected by TLS SNI).
3. Otherwise the row is skipped.

## Notes
- `ca_list` is the **trust store for the peer** (Microsoft), not the issuer of
  your own cert — `rotate` never touches it; manage it with `set-ca`.
- `certificate` should be the full chain (leaf + intermediates); lego's `.crt`
  already is.
- `opensips-cli` must be configured to reach this instance's MI (fifo or http).
