#!/usr/bin/env bash
set -euo pipefail
APK="${1:?APK path required}"
OUT="${2:-build/DPA_SIGNING_PROOF.txt}"
if [[ -z "${ANDROID_HOME:-}" ]]; then
  echo "ANDROID_HOME is not set" >&2
  exit 1
fi
APKSIGNER="$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -n1)"
if [[ -z "$APKSIGNER" ]]; then
  echo "apksigner not found" >&2
  exit 1
fi
mkdir -p "$(dirname "$OUT")"
{
  echo "DPA APK SIGNING PROOF"
  echo "====================="
  "$APKSIGNER" verify --verbose --print-certs "$APK"
} > "$OUT"
cat "$OUT"
