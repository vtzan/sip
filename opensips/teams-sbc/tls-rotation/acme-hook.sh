#!/usr/bin/env bash
# ============================================================================
#  ACME issuance/renewal hook for manage-tls.py
#
#  Called as:   acme-hook.sh <primary-fqdn> <comma-separated-SANs>
#  Must print (stdout) the resulting PEM paths:
#       CERT=/path/to/fullchain.pem
#       KEY=/path/to/privkey.pem
#
#  Default implementation uses `lego` with a DNS-01 challenge (required for
#  wildcard certificates such as *.teams.ucp.voiceland.dev). Set the ACME_*
#  environment variables (see rotation.conf / the systemd unit) for your DNS
#  provider. Swap the body for certbot/acme.sh if you prefer.
# ============================================================================
set -euo pipefail

PRIMARY="$1"
SANS="$2"

: "${ACME_EMAIL:?set ACME_EMAIL}"
: "${ACME_DNS_PROVIDER:?set ACME_DNS_PROVIDER (e.g. cloudflare, route53, gcloud)}"
LEGO_PATH="${LEGO_PATH:-/var/lib/lego}"
LEGO_SERVER="${ACME_SERVER:-https://acme-v02.api.letsencrypt.org/directory}"

# Build --domains args from the comma-separated SAN list.
DOMAIN_ARGS=()
IFS=',' read -ra _SANS <<<"$SANS"
for d in "${_SANS[@]}"; do
    DOMAIN_ARGS+=(--domains "$d")
done

mkdir -p "$LEGO_PATH"

# `run` issues a new cert; if one already exists lego errors, so fall back to
# `renew` (which is a no-op until inside the renewal window unless --days forces).
if ! lego --accept-tos --email "$ACME_EMAIL" --server "$LEGO_SERVER" \
          --dns "$ACME_DNS_PROVIDER" --path "$LEGO_PATH" \
          "${DOMAIN_ARGS[@]}" run >&2; then
    lego --accept-tos --email "$ACME_EMAIL" --server "$LEGO_SERVER" \
         --dns "$ACME_DNS_PROVIDER" --path "$LEGO_PATH" \
         "${DOMAIN_ARGS[@]}" renew --days 30 --no-random-sleep >&2
fi

# lego stores files under <path>/certificates/, replacing '*' with '_' for wildcards.
SAFE="${PRIMARY//\*/_}"
echo "CERT=${LEGO_PATH}/certificates/${SAFE}.crt"
echo "KEY=${LEGO_PATH}/certificates/${SAFE}.key"
