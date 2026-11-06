#!/bin/bash
# Runs the end-to-end scenarios against the real debug app (WKWebView + backend).
#   app/e2e/run.sh [scenario ...]     # names without .js; default: every scenario
# Each scenario gets a fresh DAPPER_DATA_DIR; screenshots land in /tmp/dapper-e2e/<scenario>/.
set -u
cd "$(dirname "$0")/.."
APP=$PWD
source "$HOME/.cargo/env"
export CARGO_TARGET_DIR="$APP/target/e2e"
BIN="$CARGO_TARGET_DIR/debug/dapper-app"
OUT=/tmp/dapper-e2e

cargo build -p dapper-app || exit 1

# Debug builds load the Vite dev server (tauri.conf.json devUrl).
VITE_PID=
if ! nc -z localhost 1420 2>/dev/null; then
  (cd ui && exec npx vite --port 1420 --strictPort >"$OUT-vite.log" 2>&1) &
  VITE_PID=$!
  for _ in $(seq 1 60); do nc -z localhost 1420 2>/dev/null && break; sleep 0.5; done
fi
trap '[ -n "$VITE_PID" ] && kill $VITE_PID 2>/dev/null' EXIT

scenarios=("$@")
[ ${#scenarios[@]} -eq 0 ] && scenarios=(first-run playback playlists device settings import lidarr)

declare -a results
for s in "${scenarios[@]}"; do
  data=$(mktemp -d /tmp/dapper-e2e-data.XXXXXX)
  rm -rf "${OUT:?}/$s"; mkdir -p "$OUT/$s"
  echo "=== $s (data $data)"
  DAPPER_DATA_DIR="$data" DAPPER_LEGACY_DIR= DAPPER_E2E_SCRIPT="$APP/e2e/$s.js" DAPPER_E2E_SHOTS="$OUT/$s" \
    RUST_LOG="${RUST_LOG:-info,dapper=debug}" "$BIN" >"$OUT/$s.log" 2>&1
  code=$?
  grep -E '^E2E: ' "$OUT/$s.log"
  results+=("$s: exit $code")
  rm -rf "$data"
done
echo "=== summary"
printf '%s\n' "${results[@]}"
