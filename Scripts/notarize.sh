#!/usr/bin/env bash
# Author: Simon-Pierre Boucher — contact@spboucher.ai
# File: Scripts/notarize.sh
# Description: Notarizes dist/SP Wallet.app with the EXISTING notarytool keychain profile, staples it, then builds, signs, notarizes and staples the DMG.
#
# Usage: Scripts/notarize.sh
#   NOTARY_PROFILE  keychain profile created earlier with `xcrun notarytool store-credentials` (default: MacLustr-Notarize).
# The script never creates, prints or modifies credentials. "notarized" is printed only when Apple answered Accepted.
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-MacLustr-Notarize}"; APPNAME="SP Wallet"; APP="dist/$APPNAME.app"
[[ -d "$APP" ]] || { echo "ERROR: $APP not found. Run Scripts/release.sh first." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/SPWallet-$VERSION.dmg"; ZIP="Build/SPWallet-notarize.zip"; mkdir -p Build

submit() {   # submit <file> <json-output>; returns 0 only when status is Accepted
  local file="$1" out="$2"
  if ! xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json >"$out" 2>"$out.err"; then
    echo "Notary service refused the submission of $file:" >&2; sed -e 's/^/  /' "$out.err" | head -8 >&2; [[ -s "$out" ]] && head -c 600 "$out" >&2 && echo >&2; return 1
  fi
  local status id
  status="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$out")"
  id="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$out")"
  echo "Submission $id: $status"
  if [[ "$status" != "Accepted" ]]; then
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" "Build/notary-log-$id.json" >/dev/null 2>&1 || true
    echo "See Build/notary-log-$id.json for the reasons." >&2; return 1
  fi
}

echo "== 1/4 Submitting the application =="
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
submit "$ZIP" Build/notary-app.json || { echo "RESULT: NOT notarized. $APP is signed but carries no notarization ticket." >&2; exit 2; }
echo "== 2/4 Stapling the application =="
xcrun stapler staple "$APP"; xcrun stapler validate "$APP"

echo "== 3/4 Building the disk image =="
IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)"
rm -f "$DMG"; STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/$APPNAME.app"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APPNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null; rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "== 4/4 Submitting and stapling the disk image =="
submit "$DMG" Build/notary-dmg.json || { echo "RESULT: the application is notarized and stapled, but the disk image is NOT." >&2; exit 3; }
xcrun stapler staple "$DMG"; xcrun stapler validate "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")") | tee "$DMG.sha256"
echo "RESULT: notarized and stapled — $APP and $DMG"
