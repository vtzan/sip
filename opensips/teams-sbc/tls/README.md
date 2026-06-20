# TLS material

Place the certificate/key referenced by `local.m4` here (paths are configurable):

| local.m4 variable | default file                         | contents                                            |
|-------------------|--------------------------------------|-----------------------------------------------------|
| `M_TLS_CERT`      | `wildcard.crt.pem`                   | SBC server/client certificate (PEM, full chain)     |
| `M_TLS_KEY`       | `wildcard.key.pem`                   | private key (PEM, **never commit**)                 |
| `M_TLS_CA`        | `ca-bundle.pem`                      | public root/intermediate chain that signs the Microsoft SIP proxy cert |

## Certificate requirements (Microsoft Teams Direct Routing)

- Issued by a [Microsoft-supported public CA](https://learn.microsoft.com/en-us/microsoftteams/direct-routing-plan#supported-session-border-controllers-sbcs)
  (e.g. DigiCert). Self-signed certificates are rejected.
- Subject / SAN must cover the tenant FQDNs the SBC presents. A wildcard works:
  - dev:  `*.teams.ucp.voiceland.dev`
  - prod: `*.teams.ucp.voiceland.global`
  - plus the base OPTIONS FQDN, e.g. `sbc.teams.ucp.voiceland.dev`
- TLS 1.2 (the config negotiates `TLSv1_2+`).
- The **same** cert/key is used for the inbound TLS server (port 5560) and the
  outbound TLS client connections to `sip*.pstnhub.microsoft.com`.

`ca-bundle.pem` must let OpenSIPS verify Microsoft's certificate (mutual TLS,
`require_cert`/`verify_cert` are enabled). The system CA bundle generally works:

```
cp /etc/ssl/certs/ca-certificates.crt ca-bundle.pem   # Debian/Ubuntu
```

Files in this directory matching `*.pem`, `*.key`, `*.crt`, `*.p12`, `*.pfx`
are git-ignored.
