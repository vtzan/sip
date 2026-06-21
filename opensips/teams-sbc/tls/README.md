# TLS material

> **Certificates are now managed in the database** (`tls_mgm` table), not in
> files. See [`../tls-rotation/`](../tls-rotation/). This directory is only a
> scratch area for the ACME client (lego) output and the CA bundle you import.

## What lives where

| Item                         | Location                                                        |
|------------------------------|----------------------------------------------------------------|
| SBC certificate + private key| `tls_mgm.certificate` / `tls_mgm.private_key` (BLOB)            |
| Peer-verification CA bundle  | `tls_mgm.ca_list` (BLOB) — set with `manage-tls.py set-ca`     |
| Issuance / renewal           | `tls-rotation/manage-tls.py rotate` (ACME, daily systemd timer)|

## Certificate requirements (Microsoft Teams Direct Routing)

- Issued by a [Microsoft-supported public CA](https://learn.microsoft.com/en-us/microsoftteams/direct-routing-plan#supported-session-border-controllers-sbcs).
- Subject/SAN must cover the tenant FQDNs the SBC presents. A wildcard works:
  - dev:  `*.teams.ucp.voiceland.dev`
  - prod: `*.teams.ucp.voiceland.global`
  - plus the base OPTIONS FQDN, e.g. `sbc.teams.ucp.voiceland.dev`
- TLS 1.2 (the `tls_mgm` rows negotiate `TLSv1_2+`).

## Bootstrapping the CA bundle

`ca_list` must let OpenSIPS verify the **Microsoft** peer certificate (mutual
TLS). The system bundle generally works:

```bash
cp /etc/ssl/certs/ca-certificates.crt ca-bundle.pem     # Debian/Ubuntu
python3 ../tls-rotation/manage-tls.py set-ca --ca ca-bundle.pem
```

Files in this directory matching `*.pem`, `*.key`, `*.crt`, `*.p12`, `*.pfx`
are git-ignored.
