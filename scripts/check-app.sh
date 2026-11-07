#!/bin/bash
# check-app.sh sign <Swivel.app>: hardened runtime, only the apple-events entitlement, strict verify, Swivel Dev DR.
# Prints one FAIL line per failed check; exits non-zero if any failed. Used by qa.sh and release.sh.
set -uo pipefail
mode=$1 app=$2
bad=0
no() { echo "FAIL $1"; bad=1; }
case $mode in
  sign)
    info=$(codesign -dvv "$app" 2>&1)
    [[ "$info" =~ flags=0x[0-9a-f]+\([a-z,]*runtime ]] || no "no hardened runtime flag"
    ents=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null)
    [ "$ents" = '{"com.apple.security.automation.apple-events":true}' ] || no "entitlements are '$ents'"
    codesign --verify --strict --deep "$app" 2>/dev/null || no "codesign --verify --strict --deep"
    # The leaf hash pins the Swivel Dev cert, so Finder access and the login item survive updates.
    if grep -q '^Authority=Swivel Dev$' <<<"$info"; then
      dr='identifier "dev.zubair.swivel" and certificate leaf = H"ec07fa7abf92c18dfab000fd7642fa734ac19e63"'
      [[ "$(codesign -d -r- "$app" 2>&1)" == *"designated => $dr"* ]] || no "designated requirement is not the Swivel Dev one"
    fi
    ;;
  *) no "unknown mode $mode" ;;
esac
exit $bad
