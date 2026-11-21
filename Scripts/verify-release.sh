#!/usr/bin/env bash
# =============================================================================
#                  SP BOUCHER | INFRASTRUCTURE & AUTOMATION
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# Project          : SP Wallet for macOS
# File             : Scripts/verify-release.sh
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
# File: Scripts/verify-release.sh
# Description: Checks the signed SP Wallet application: signature, hardened runtime, sandbox and entitlements, embedded profile, no web engine, no debug entitlement, no development code or test server, no secret in the bundle, production endpoint only.
#
# Usage: Scripts/verify-release.sh [path/to/SP Wallet.app]   (exit code ≠ 0 when a check fails)
set -uo pipefail
cd "$(dirname "$0")/.."
APP="${1:-dist/SP Wallet.app}"; BIN="$APP/Contents/MacOS/SP Wallet"; FAIL=0
ok() { echo "  ✓ $1"; }; ko() { echo "  ✗ $1"; FAIL=1; }
[[ -d "$APP" ]] || { echo "ERROR: $APP not found" >&2; exit 1; }
echo "== Signature"
codesign --verify --deep --strict "$APP" 2>/dev/null && ok "codesign --verify --deep --strict" || ko "signature invalid"
INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$INFO" && ok "$(grep -m1 '^Authority=' <<<"$INFO")" || ko "not signed with Developer ID Application"
grep -Eq "flags=.*runtime" <<<"$INFO" && ok "hardened runtime enabled" || ko "hardened runtime missing"
grep -q "^Timestamp=" <<<"$INFO" && ok "secure timestamp present" || ko "no secure timestamp"
grep -q "^Identifier=ai.spboucher.spwallet$" <<<"$INFO" && ok "Identifier=ai.spboucher.spwallet" || ko "unexpected identifier: $(grep -m1 '^Identifier=' <<<"$INFO")"
grep -q "^TeamIdentifier=3YM54G49SN$" <<<"$INFO" && ok "TeamIdentifier=3YM54G49SN" || ko "unexpected team"
echo "== Entitlements"
ENT="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
grep -A1 "com.apple.security.app-sandbox" <<<"$ENT" | grep -q "<true/>" && ok "App Sandbox on" || ko "App Sandbox off"
grep -A1 "com.apple.security.network.client" <<<"$ENT" | grep -q "<true/>" && ok "outgoing network only" || ko "network client entitlement missing"
grep -q "webcredentials:wallet.spboucher.ai" <<<"$ENT" && ok "associated domain webcredentials:wallet.spboucher.ai (passkeys)" || ko "associated domain missing (passkeys would fail)"
[[ "$(grep -c "webcredentials:" <<<"$ENT")" == 1 ]] && ok "no other associated domain" || ko "unexpected associated domains"
grep -q "get-task-allow" <<<"$ENT" && ko "get-task-allow present (debug entitlement)" || ok "no get-task-allow"
for bad in com.apple.security.cs.disable-library-validation com.apple.security.cs.allow-unsigned-executable-memory com.apple.security.cs.allow-jit com.apple.security.cs.allow-dyld-environment-variables com.apple.security.network.server com.apple.security.device.camera com.apple.security.device.audio-input com.apple.security.files.all com.apple.security.files.downloads.read-write com.apple.security.automation.apple-events com.apple.security.temporary-exception; do
  grep -q "$bad" <<<"$ENT" && ko "unexpected entitlement $bad"; done; ok "no runtime exception, no server socket, no device, no broad file access, no Apple events"
[[ -f "$APP/Contents/embedded.provisionprofile" ]] && ok "provisioning profile embedded" || ko "embedded.provisionprofile missing"
echo "== Native only"
LIBS="$(for a in $(lipo -archs "$BIN"); do otool -arch "$a" -L "$BIN"; done; find "$APP/Contents" -name '*.dylib' -o -name '*.framework')"
grep -Eiq "WebKit|JavaScriptCore|Electron|Chromium|libnode" <<<"$LIBS" && ko "a web engine is linked" || ok "no WebKit / JavaScriptCore / Chromium linked"
nm -u "$BIN" 2>/dev/null | grep -Eq "WKWebView|WebView" && ko "a web view symbol is referenced" || ok "no web view symbol referenced"
find "$APP" \( -name '*.html' -o -name '*.js' -o -name '*.css' \) | grep -q . && ko "web resources in the bundle" || ok "no HTML / JS / CSS resources"
echo "== Release, not development"
STR="$(strings -a "$BIN")"
grep -Eq "spwDevPort|spwAutoSetup|spwSelfTest|spwDevSetupToken|dev-passkey|DevPasskey|SoftwareAuthenticator|localhost:87|spwallet\.dev" <<<"$STR" && ko "development switch, software passkey or test server in the binary" || ok "no development switch, no software passkey, no test server, no .dev identifier"
grep -q "https://wallet.spboucher.ai" <<<"$STR" && ok "production endpoint https://wallet.spboucher.ai" || ko "production endpoint not found"
grep -Eo "http://[a-zA-Z0-9.-]+" <<<"$STR" | grep -Ev "www\.apple\.com|www\.w3\.org|ns\.adobe\.com|purl\.org|schemas\.|xmlsoap" | sort -u | grep -q . && ko "plain-http URL in the binary: $(grep -Eo "http://[a-zA-Z0-9.-]+" <<<"$STR" | sort -u | head -3 | tr '\n' ' ')" || ok "no plain-http endpoint"
grep -q "NSAllowsLocalNetworking\|NSAllowsArbitraryLoads" "$APP/Contents/Info.plist" && ko "App Transport Security exception present" || ok "no App Transport Security exception"
echo "== Secrets"
if grep -rlaE "(sk-ant-|sk-proj-|BEGIN (EC |RSA |OPENSSH )?PRIVATE KEY|Bearer [A-Za-z0-9_-]{40}|spw_live_[A-Za-z0-9]{20})" "$APP" >/dev/null 2>&1; then ko "something that looks like a secret is in the bundle"; else ok "no API key, private key or session token in the bundle"; fi
grep -Eiq "mnemonic|seed phrase|export-recovery|privateKey\b" <<<"$STR" && echo "  · note: recovery-related words appear in UI strings (review: $(grep -Eio "mnemonic|seed phrase|export-recovery" <<<"$STR" | sort -u | tr '\n' ' '))" || ok "no seed / private-key handling string"
echo "== Bundle"
echo "  version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")) · archs $(lipo -archs "$BIN") · min macOS $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist") · $(du -sh "$APP" | cut -f1)"
[[ -f "$APP/Contents/Resources/AppIcon.icns" || -f "$APP/Contents/Resources/Assets.car" ]] && ok "icon assets present" || ko "icon missing"
exit $FAIL
