#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
ENV_FILE="${1:-.env.production}"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
mkdir -p backups
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="backups/dpa_${STAMP}.dump"
docker compose --env-file "$ENV_FILE" exec -T postgres \
  pg_dump -U "${DPA_POSTGRES_USER:-dpa}" -d "${DPA_POSTGRES_DB:-dpa}" -Fc > "$OUT"
sha256sum "$OUT" > "$OUT.sha256"
printf 'Backup: %s\nChecksum: %s\n' "$OUT" "$OUT.sha256"
