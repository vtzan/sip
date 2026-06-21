#!/usr/bin/env bash
# ============================================================================
#  Resolve the core discovery FQDN to its current A records and sync them into
#  the permissions `address` table (group CORE_GROUP), then reload OpenSIPS.
#  Run every 5 minutes by the sidecar.
#
#    dev  : CORE_IPS_FQDN=eu.ucp.voiceland.dev
#    prod : CORE_IPS_FQDN=ips.ucp.voiceland.global   (resolves to 2 IPs)
# ============================================================================
set -euo pipefail
: "${CORE_IPS_FQDN:?set CORE_IPS_FQDN}"
: "${DB_HOST:=127.0.0.1}" "${DB_PORT:=3306}" "${DB_USER:=opensips}" "${DB_PASS:=opensipsrw}" "${DB_NAME:=opensips}"
: "${CORE_GROUP:=1}"
: "${MI_URL:=http://127.0.0.1:8888/mi}"

IPS="$(getent ahostsv4 "$CORE_IPS_FQDN" | awk '{print $1}' | sort -u)"
if [ -z "$IPS" ]; then
    echo "[core-ips] WARNING: no A records for $CORE_IPS_FQDN (leaving table unchanged)"
    exit 0
fi

SQL="START TRANSACTION; DELETE FROM address WHERE grp=$CORE_GROUP;"
for ip in $IPS; do
    SQL="$SQL INSERT INTO address (grp, ip, mask, port, proto) VALUES ($CORE_GROUP, '$ip', 32, 0, 'any');"
done
SQL="$SQL COMMIT;"

echo "[core-ips] $CORE_IPS_FQDN -> $(echo $IPS | tr '\n' ' ')"
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"

curl -fsS "$MI_URL" -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"address_reload"}' >/dev/null \
     && echo "[core-ips] address_reload OK" \
     || echo "[core-ips] address_reload failed (is OpenSIPS up?)"
