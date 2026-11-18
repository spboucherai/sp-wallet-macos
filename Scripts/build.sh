#!/usr/bin/env bash
# Author: Simon-Pierre Boucher — contact@spboucher.ai
# File: Scripts/build.sh
# Description: Generates the Xcode project and builds SP Wallet (errors only on the console).
#
# Usage: Scripts/build.sh [Debug|Release] [derived-data-suffix]     Debug = the development variant "SP Wallet Dev".
# Products go outside ~/Desktop. Several builds may run at once when each uses its own suffix; project generation is serialized.
set -uo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"; SUF="${2:-}"; DD="$HOME/Library/Developer/SPWallet/DerivedData${SUF:+-$SUF}"; mkdir -p Build "$DD"
LOG="Build/build${SUF:+-$SUF}.log"
until mkdir Build/.gen.lock 2>/dev/null; do sleep 0.3; done; xcodegen generate --quiet; rmdir Build/.gen.lock
EXTRA=(); [[ "$CONFIG" == Debug && ! -d Build/profiles ]] && EXTRA=(CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= CODE_SIGN_ENTITLEMENTS=Resources/SPWallet-DevAdhoc.entitlements)
xcodebuild -project SPWallet.xcodeproj -scheme SPWallet -configuration "$CONFIG" -derivedDataPath "$DD" build ${EXTRA[@]+"${EXTRA[@]}"} 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$LOG"
grep -E "error:|BUILD" "$LOG" | sed -E "s#$PWD/##" | grep -v "^ *|" | sort -u | cut -c1-320 | head -"${LINES_MAX:-60}"
grep -q "BUILD SUCCEEDED" "$LOG"
