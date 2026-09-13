#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-dpa-release.jks}"
ALIAS="${2:-dpa-release}"
if [[ -e "$OUT" ]]; then
  echo "Refusing to overwrite existing $OUT" >&2
  exit 1
fi
command -v keytool >/dev/null 2>&1 || { echo "keytool/JDK is required." >&2; exit 1; }
echo "A password will be requested by keytool. Keep the keystore and passwords private and backed up."
keytool -genkeypair \
  -keystore "$OUT" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -dname "CN=Delta Peak APP, OU=DPA, O=Delta Peak, C=IR"
echo "Created: $OUT"
echo "Alias: $ALIAS"
echo "Next: store the keystore as GitHub secret DPA_ANDROID_KEYSTORE_BASE64 and its passwords/alias as separate secrets."
