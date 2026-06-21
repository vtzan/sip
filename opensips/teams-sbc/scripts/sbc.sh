#!/usr/bin/env bash
# ============================================================================
#  Run docker compose for a specific SBC instance + environment.
#
#  Usage:  scripts/sbc.sh <instance> <dev|prod> <docker compose args...>
#  Example:
#     scripts/sbc.sh sbc1 dev  up -d --build
#     scripts/sbc.sh sbc1 prod logs -f opensips
#     scripts/sbc.sh sbc2 dev  down
#
#  Selects .env.<instance>.<env> (which sets COMPOSE_PROJECT_NAME + ENV_FILE).
#  Run from the teams-sbc directory (where docker-compose.yml lives).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

INST="${1:?usage: sbc.sh <instance> <dev|prod> <compose args...>}"
ENVN="${2:?usage: sbc.sh <instance> <dev|prod> <compose args...>}"
shift 2

case "$ENVN" in dev|prod) ;; *) echo "env must be 'dev' or 'prod', got '$ENVN'" >&2; exit 2 ;; esac

FILE=".env.${INST}.${ENVN}"
if [ ! -f "$FILE" ]; then
    echo "missing env file: $FILE" >&2
    echo "  create it from the template, e.g.:  cp ${FILE}.example $FILE" >&2
    exit 1
fi

exec docker compose --env-file "$FILE" "$@"
