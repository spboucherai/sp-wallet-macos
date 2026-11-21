#!/usr/bin/env bash
# =============================================================================
#                  SP BOUCHER | INFRASTRUCTURE & AUTOMATION
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# Project          : SP Wallet for macOS
# File             : Scripts/release.sh
# Module           : Scripts
# Repository       : https://git.spboucher.ai/sp-wallet-macos
# Created          : 2026-11-18
# Last Modified    : 2026-11-18
#
# Author           : Simon-Pierre Boucher
# Position         : Professor of Finance
# Institution      : Université du Québec en Outaouais (UQO)
# Organization     : SP Boucher
# Website          : https://spboucher.ai
# Git              : https://git.spboucher.ai
#
# Preferred Contact: support@spboucher.ai
# Technical Contact: dev@spboucher.ai
# Security/Admin   : admin@spboucher.ai
#
# Copyright (c) 2026
# Simon-Pierre Boucher
# All rights reserved where applicable. This file is governed by the
# applicable project license, copyright notices and relevant law.
# Existing third-party rights and notices remain unaffected.
#
# License          : None specified (no license file in this repository)
#
# Do not embed credentials, private keys, access tokens,
# certificates or confidential personal information.
#
# =============================================================================
# END OF SP BOUCHER SOURCE HEADER
# =============================================================================

# Author: Simon-Pierre Boucher — contact@spboucher.ai
# File: Scripts/release.sh
# Description: Builds the Release archive of SP Wallet signed with the EXISTING Developer ID Application identity and the Developer ID provisioning profiles, and exports dist/SP Wallet.app.
#
# Usage: Scripts/release.sh
# Nothing secret is printed. No certificate is created: the script fails if no Developer ID Application identity exists.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"; LOG="$ROOT/Build/release-build.log"; APPNAME="SP Wallet"; DD="$HOME/Library/Developer/SPWallet/DerivedData-Release"
mkdir -p Build dist

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
[[ -n "$IDENTITY" ]] || { echo "ERROR: no 'Developer ID Application' identity in the keychain." >&2; exit 1; }
TEAM="$(sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' <<<"$IDENTITY")"
echo "Signing identity : $IDENTITY"
echo "Team             : $TEAM"

# the provisioning profiles carry the restricted entitlements (associated domains for passkeys, keychain group)
for f in SPWallet; do
  SRC="$ROOT/Build/profiles/$f.provisionprofile"
  [[ -f "$SRC" ]] || { echo "ERROR: $SRC missing (create it with Scripts/provision.py)." >&2; exit 1; }
  PLIST="$(mktemp)"; security cms -D -i "$SRC" > "$PLIST" 2>/dev/null
  UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PLIST")"; PNAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$PLIST")"; EXPIRES="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$PLIST")"; rm -f "$PLIST"
  for d in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do mkdir -p "$d"; cp "$SRC" "$d/$UUID.provisionprofile"; done
  echo "Profile          : $PNAME ($UUID), expires $EXPIRES"
done

xcodegen generate --quiet
ARCHIVE="$ROOT/Build/SPWallet.xcarchive"
rm -rf "$ARCHIVE" "$ROOT/dist/$APPNAME.app"
echo "Archiving (log: Build/release-build.log)…"
if ! xcodebuild -project SPWallet.xcodeproj -scheme SPWallet -configuration Release -derivedDataPath "$DD" \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive DEVELOPMENT_TEAM="$TEAM" >"$LOG" 2>&1; then
  grep -E "error:|ARCHIVE FAILED" "$LOG" | sort -u | head -30 >&2
  echo "ERROR: archive failed, see $LOG" >&2; exit 1
fi
ditto "$ARCHIVE/Products/Applications/$APPNAME.app" "$ROOT/dist/$APPNAME.app"
APP="dist/$APPNAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"; BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "Built $APP  version $VERSION ($BUILD)  archs: $(lipo -archs "$APP/Contents/MacOS/$APPNAME")"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
echo "Next: Scripts/verify-release.sh, then Scripts/notarize.sh"
