#!/usr/bin/env bash
# ============================================================================
#  Create / enable a tenant that can SEND to and RECEIVE from Microsoft Teams.
#
#  A tenant is a row in the tls_mgm table keyed by its FQDN (the SBC presents
#  this tenant's certificate by TLS SNI, and outbound calls are accepted only
#  when From/PAI host matches a tls_mgm tenant).
#
#  Usage:
#     scripts/create-tenant.sh <tenant-fqdn> [--cert fullchain.pem --key key.pem]
#
#  Run on the host (with mysql client + python deps) or inside the container:
#     docker compose exec opensips /etc/opensips/teams-sbc/scripts/create-tenant.sh acme.teams.ucp.voiceland.dev
#
#  With no --cert/--key a temporary self-signed cert is installed so the tenant
#  works immediately; the daily ACME rotation then issues a trusted certificate.
# ============================================================================
set -euo pipefail
SBC="${SBC_DIR:-/etc/opensips/teams-sbc}"
: "${DB_HOST:=127.0.0.1}" "${DB_PORT:=3306}" "${DB_USER:=opensips}" "${DB_PASS:=opensipsrw}" "${DB_NAME:=opensips}"

FQDN="${1:?usage: create-tenant.sh <tenant-fqdn> [--cert F --key F]}"; shift || true
CERT=""; KEY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --cert) CERT="$2"; shift 2 ;;
        --key)  KEY="$2";  shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

CIPHERS='HIGH:!aNULL:!eNULL:!MD5:!RC4:!3DES:!EXPORT'
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT INTO tls_mgm (domain, type, match_sip_domain, method, verify_cert, require_cert, cipher_list)
VALUES ('$FQDN', 2, '$FQDN', 'TLSv1_2+', 1, 1, '$CIPHERS')
ON DUPLICATE KEY UPDATE match_sip_domain=VALUES(match_sip_domain),
                        method=VALUES(method), cipher_list=VALUES(cipher_list);
SQL
echo "[create-tenant] tls_mgm row ensured for $FQDN"

CONF="$SBC/tls-rotation/rotation.conf"
[ -f "$CONF" ] || CONF="$SBC/tls-rotation/rotation.conf.example"
MTLS=(python3 "$SBC/tls-rotation/manage-tls.py" --config "$CONF")
CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

"${MTLS[@]}" set-ca --ca "$CA_BUNDLE" --domain "$FQDN" || true

if [ -n "$CERT" ] && [ -n "$KEY" ]; then
    "${MTLS[@]}" load --domain "$FQDN" --cert "$CERT" --key "$KEY"
else
    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
        -keyout "$TMP/key.pem" -out "$TMP/crt.pem" \
        -subj "/CN=$FQDN" -addext "subjectAltName=DNS:$FQDN"
    "${MTLS[@]}" load --domain "$FQDN" --cert "$TMP/crt.pem" --key "$TMP/key.pem"
    echo "[create-tenant] self-signed cert installed; ACME rotation will replace it"
fi

echo "[create-tenant] done -- $FQDN can now send to and receive from MS Teams"
