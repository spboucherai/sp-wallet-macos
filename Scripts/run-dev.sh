#!/usr/bin/env bash
# Author: Simon-Pierre Boucher — contact@spboucher.ai
# File: Scripts/run-dev.sh
# Description: Launches the development variant "SP Wallet Dev" against the local throwaway stack (../SPWalletCore/Scripts/dev-stack.sh, SPW_NATIVE_PORT=8760).
#
# Usage: Scripts/run-dev.sh [--section <name>] [--selftest] [--halt] [--shot out.png] [--keep]
#   The app is copied out of DerivedData to ~/Applications/SPWalletDev so that it never runs from ~/Desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${SPW_NATIVE_PORT:-8760}"; DD="$HOME/Library/Developer/SPWallet/DerivedData"; SRC="$DD/Build/Products/Debug/SP Wallet Dev.app"
DST="$HOME/Applications/SPWalletDev/SP Wallet Dev.app"; BIN="$DST/Contents/MacOS/SP Wallet Dev"
ARGS=(-spwDevPort "$PORT" -spwAutoSetup YES); SHOT=""; KEEP=0; SELF=0
while [[ $# -gt 0 ]]; do case "$1" in
  --section) ARGS+=(-spwSection "$2"); shift 2 ;;
  --selftest) ARGS+=(-spwSelfTest YES); SELF=1; shift ;;
  --halt) ARGS+=(-spwSelfTestHalt YES); shift ;;
  --shot) SHOT="$2"; shift 2 ;;
  --keep) KEEP=1; shift ;;
  *) echo "unknown option $1"; exit 2 ;;
esac; done
[[ -d "$SRC" ]] || { echo "build first: Scripts/build.sh Debug"; exit 1; }
TOKEN_FILE="/tmp/spw-native-$PORT/current/setup-token"; [[ -f "$TOKEN_FILE" ]] && ARGS+=(-spwDevSetupToken "$(tr -d '\n' < "$TOKEN_FILE")")
# stop a previous run of the DEV variant only, by the PID of its own binary path
for pid in $(pgrep -f "$BIN" 2>/dev/null || true); do kill "$pid" 2>/dev/null || true; done; sleep 0.5
mkdir -p "$(dirname "$DST")"; rm -rf "$DST"; ditto "$SRC" "$DST"
CONT="$HOME/Library/Containers/ai.spboucher.spwallet.dev/Data/Library/Application Support/SPWallet"
[[ $SELF == 1 ]] && rm -f "$CONT/selftest.json"
"$BIN" "${ARGS[@]}" >/dev/null 2>&1 &
PID=$!
if [[ $SELF == 1 ]]; then
  for _ in $(seq 1 240); do [[ -f "$CONT/selftest.json" ]] && break
    # fork mode: the local anvil fork only mines when asked — mine a block so confirmations can accumulate
    curl -s -m 1 -X POST -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"anvil_mine","params":["0x2"]}' "http://127.0.0.1:$((PORT + 2))" >/dev/null 2>&1 || true
    sleep 1; done
  [[ -f "$CONT/selftest.json" ]] && python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); [print(("PASS " if x["ok"] else "FAIL ")+x["name"]+("  — "+x["detail"] if x["detail"] else "")) for x in r]; print("%d/%d"%(sum(x["ok"] for x in r),len(r)))' "$CONT/selftest.json" || echo "self-test produced no result"
fi
if [[ -n "$SHOT" ]]; then sleep "${SHOT_DELAY:-6}"; swift Scripts/window-shot.swift "SP Wallet Dev" "$SHOT" | tail -1; fi
[[ $KEEP == 1 ]] || { kill $PID 2>/dev/null || true; }
