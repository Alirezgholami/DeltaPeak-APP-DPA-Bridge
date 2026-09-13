#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
ENV_FILE="${1:-.env.production}"
python scripts/production_preflight.py "$ENV_FILE"
command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 1; }
docker compose --env-file "$ENV_FILE" config >/dev/null
docker compose --env-file "$ENV_FILE" build --pull api
docker compose --env-file "$ENV_FILE" up -d --remove-orphans
printf '%s\n' "DPA services started. Check with: docker compose --env-file $ENV_FILE ps"
