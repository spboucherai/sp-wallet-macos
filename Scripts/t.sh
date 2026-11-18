#!/usr/bin/env bash
# Author: Simon-Pierre Boucher — contact@spboucher.ai
# File: Scripts/t.sh
# Description: Runs the app's unit tests (Swift Testing, hosted in the development variant). The test build is signed ad hoc without the hardened runtime: an injected test bundle is refused by a hardened Developer ID host.
#
# Usage: Scripts/t.sh [derived-data-suffix]
set -uo pipefail
cd "$(dirname "$0")/.."
SUF="${1:-test}"; DD="$HOME/Library/Developer/SPWallet/DerivedData-$SUF"; mkdir -p Build
until mkdir Build/.gen.lock 2>/dev/null; do sleep 0.3; done; xcodegen generate --quiet; rmdir Build/.gen.lock
cat > Build/test-adhoc.entitlements <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
ENT
xcodebuild -project SPWallet.xcodeproj -scheme SPWallet -configuration Debug -derivedDataPath "$DD" test \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER= ENABLE_HARDENED_RUNTIME=NO CODE_SIGN_ENTITLEMENTS="$PWD/Build/test-adhoc.entitlements" OTHER_CODE_SIGN_FLAGS= \
  2>&1 | sed 's/\x1b\[[0-9;]*m//g' > Build/test.log
grep -E "error:|✘|Test run with|recorded an issue|\*\* TEST" Build/test.log | sed -E "s#$PWD/##" | sort -u | cut -c1-300 | head -40
grep -q "TEST SUCCEEDED" Build/test.log
