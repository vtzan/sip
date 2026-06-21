#!/usr/bin/env bash
# ============================================================================
#  First-boot certificate bootstrap.
#  Generates ONE self-signed certificate covering the base/wildcard FQDNs and
#  loads it into the teams_srv + teams_cli tls_mgm rows so OpenSIPS can start.
#  These are NOT trusted by Microsoft -- the daily ACME rotation replaces them.
# ============================================================================
set -euo pipefail
SBC="${SBC_DIR:-/etc/opensips/teams-sbc}"
: "${BOOTSTRAP_CN:=sbc.teams.ucp.voiceland.dev}"
: "${BOOTSTRAP_SANS:=DNS:*.teams.ucp.voiceland.dev,DNS:*.teams.ucp.voiceland.global,DNS:eu.ucp.voiceland.dev,DNS:eu.ucp.voiceland.global,DNS:sbc.teams.ucp.voiceland.dev}"

CONF="$SBC/tls-rotation/rotation.conf"
[ -f "$CONF" ] || CONF="$SBC/tls-rotation/rotation.conf.example"
CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
MTLS=(python3 "$SBC/tls-rotation/manage-tls.py" --config "$CONF")

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/boot.key" -out "$TMP/boot.crt" \
    -subj "/CN=$BOOTSTRAP_CN" -addext "subjectAltName=$BOOTSTRAP_SANS"

# set-ca / load also try to MI-reload; OpenSIPS is not up yet, so that warns
# (harmless) -- the DB rows are still written.
"${MTLS[@]}" set-ca --ca "$CA_BUNDLE" || true
"${MTLS[@]}" load --domain teams_srv --cert "$TMP/boot.crt" --key "$TMP/boot.key" || true
"${MTLS[@]}" load --domain teams_cli --cert "$TMP/boot.crt" --key "$TMP/boot.key" || true

echo "[bootstrap] self-signed certificates installed into tls_mgm"
