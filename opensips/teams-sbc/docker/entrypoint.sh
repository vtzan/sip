#!/usr/bin/env bash
# ============================================================================
#  OpenSIPS container entrypoint
#    1. wait for the database
#    2. apply schema + base TLS rows (idempotent)
#    3. FIRST BOOTSTRAP: if no server certificate exists yet, generate a
#       self-signed one so OpenSIPS can open its TLS socket and start
#    4. build opensips.cfg from the m4 template
#    5. exec OpenSIPS
# ============================================================================
set -euo pipefail
SBC="${SBC_DIR:-/etc/opensips/teams-sbc}"
: "${DB_HOST:=127.0.0.1}" "${DB_PORT:=3306}" "${DB_USER:=opensips}" "${DB_PASS:=opensipsrw}" "${DB_NAME:=opensips}"
MYSQL=(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME")

echo "[entrypoint] waiting for database $DB_HOST:$DB_PORT ..."
until "${MYSQL[@]}" -e 'SELECT 1' >/dev/null 2>&1; do sleep 2; done

echo "[entrypoint] applying schema + base rows"
"${MYSQL[@]}" < "$SBC/sql/01-schema.sql"
"${MYSQL[@]}" < "$SBC/sql/02-seed-example.sql"

HAS=$("${MYSQL[@]}" -N -B -e \
    "SELECT certificate IS NOT NULL FROM tls_mgm WHERE domain='teams_srv' AND type=2" 2>/dev/null || echo "")
if [ "$HAS" != "1" ]; then
    echo "[entrypoint] FIRST BOOTSTRAP -> generating self-signed certificates"
    "$SBC/docker/gen-bootstrap-certs.sh"
else
    echo "[entrypoint] server certificate already present, skipping bootstrap"
fi

echo "[entrypoint] building opensips.cfg"
make -C "$SBC" >/dev/null

echo "[entrypoint] starting OpenSIPS"
exec opensips -F -f "$SBC/opensips.cfg"
