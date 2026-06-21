#!/usr/bin/env bash
# ============================================================================
#  Rotation sidecar:
#    * refresh the trusted core IPs from DNS every 5 minutes
#    * renew TLS certificates that are within the renewal window (default daily)
# ============================================================================
set -euo pipefail
SBC="${SBC_DIR:-/etc/opensips/teams-sbc}"
CONF="$SBC/tls-rotation/rotation.conf"
[ -f "$CONF" ] || CONF="$SBC/tls-rotation/rotation.conf.example"
: "${ROTATE_INTERVAL:=86400}"   # seconds between cert-rotation passes
: "${CORE_REFRESH_INTERVAL:=300}"

echo "[sidecar] core-IP refresh every ${CORE_REFRESH_INTERVAL}s; cert rotation every ${ROTATE_INTERVAL}s"
LAST_ROTATE=0
while true; do
    "$SBC/docker/refresh-core-ips.sh" || echo "[sidecar] core-ip refresh failed"

    NOW="$(date +%s)"
    if [ $((NOW - LAST_ROTATE)) -ge "$ROTATE_INTERVAL" ]; then
        python3 "$SBC/tls-rotation/manage-tls.py" --config "$CONF" rotate \
            || echo "[sidecar] cert rotation failed"
        LAST_ROTATE="$NOW"
    fi

    sleep "$CORE_REFRESH_INTERVAL"
done
