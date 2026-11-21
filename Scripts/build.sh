#!/usr/bin/env bash
# =============================================================================
#                  SP BOUCHER | INFRASTRUCTURE & AUTOMATION
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# Project          : SP Wallet for macOS
# File             : Scripts/build.sh
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
