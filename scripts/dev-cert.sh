#!/bin/bash
# One-time: makes a self-signed "Swivel Dev" code-signing identity in the login keychain,
# so rebuilds keep the same signature and privacy grants (Automation) survive them.
set -euo pipefail
NAME="Swivel Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "$NAME already exists"; exit 0; fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
PASS=$(uuidgen)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -passout "pass:$PASS" -out "$TMP/id.p12"
# -T lets codesign use the key without a keychain prompt.
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign
echo "Created $NAME"
