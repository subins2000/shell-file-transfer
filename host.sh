#!/usr/bin/env bash

# Copyright (C) 2026 Subin Siby <mail@subinsb.com>
# License: AGPL-3.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PORT="${SFT_PORT:-8090}"
ENCRYPT=0
PYTHON_SERVER_PID=""
CLOUDFLARED_PID=""
CLOUDFLARED_LOG="$(mktemp "${TMPDIR:-/tmp}/sft-cloudflared.XXXXXX")"

for arg in "$@"; do
  case "$arg" in
    --encrypt) ENCRYPT=1 ;;
    -h|--help)
      echo "Usage: ./host.sh [--encrypt]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --encrypt)" >&2
      exit 1
      ;;
  esac
done

cleanup() {
  set +e
  if [[ -n "${CLOUDFLARED_PID}" ]] && kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
    kill "$CLOUDFLARED_PID" 2>/dev/null
    wait "$CLOUDFLARED_PID" 2>/dev/null
  fi
  if [[ -n "${PYTHON_SERVER_PID}" ]] && kill -0 "$PYTHON_SERVER_PID" 2>/dev/null; then
    kill "$PYTHON_SERVER_PID" 2>/dev/null
    wait "$PYTHON_SERVER_PID" 2>/dev/null
  fi
  rm -f "$CLOUDFLARED_LOG"
}
trap cleanup EXIT INT TERM

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

start_python_server() {
  need python3
  mkdir -p storage
  python3 "$ROOT/server.py" --host 0.0.0.0 --port "$PORT" &
  PYTHON_SERVER_PID=$!
  # brief readiness wait (stdlib only — no curl required on host)
  for _ in $(seq 1 20); do
    if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PORT}/', timeout=1)" 2>/dev/null; then
      echo "Python server running with PID: $PYTHON_SERVER_PID"
      return 0
    fi
    sleep 0.25
  done
  echo "Python server failed to start on port $PORT" >&2
  exit 1
}

start_tunnel() {
  echo "Starting tunnel..."
  need cloudflared
  cloudflared tunnel --url "http://localhost:${PORT}" --no-autoupdate \
    >"$CLOUDFLARED_LOG" 2>&1 &
  CLOUDFLARED_PID=$!

  TUNNEL_URL=""
  for _ in $(seq 1 30); do
    TUNNEL_URL="$(grep -m1 -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" || true)"
    if [[ -n "$TUNNEL_URL" ]]; then
      break
    fi
    sleep 1
  done

  if [[ -z "$TUNNEL_URL" ]]; then
    echo "Tunnel URL not found after waiting. Cloudflared log:" >&2
    cat "$CLOUDFLARED_LOG" >&2
    exit 1
  fi
  export TUNNEL_URL
}

print_usage() {
  if [[ "$ENCRYPT" -eq 1 ]]; then
    cat <<EOF
Copy-paste any of the *_enc scripts in clients/ folder into your remote shell. Or run these one-liners in your remote shell:

# Ruby
ENV["SFT_HOST"]='${TUNNEL_URL}'; ENV["SFT_KEY"]='${SFT_KEY}'; require "net/http"; require "uri"; require "openssl"; eval Net::HTTP.get(URI("#{ENV['SFT_HOST']}/clients/ruby_enc.rb"))

sft_send "path.txt"
sft_receive "path.txt"

# Bash
export SFT_HOST='${TUNNEL_URL}'; export SFT_KEY='${SFT_KEY}'; eval "\$(curl -fsSL "\$SFT_HOST/clients/bash_enc.sh")"

sft_send "path.txt"
sft_receive "path.txt"
EOF
  else
    cat <<EOF
Copy-paste any of the scripts in clients/ folder into your remote shell. Or run these one-liners in your remote shell:

# Ruby
ENV["SFT_HOST"]='${TUNNEL_URL}';require "net/http"; require "uri"; eval Net::HTTP.get(URI("#{ENV['SFT_HOST']}/clients/ruby.rb"))

sft_send "path.txt"
sft_receive "path.txt"

# Bash
export SFT_HOST='${TUNNEL_URL}'; eval "\$(curl -fsSL "\$SFT_HOST/clients/bash.sh")"

sft_send "path.txt"
sft_receive "path.txt"
EOF
  fi
}

if [[ "$ENCRYPT" -eq 1 ]]; then
  need openssl
  SFT_KEY="$(openssl rand -base64 32)"
  export SFT_KEY
  echo "Encryption enabled for this session."
fi

start_python_server
start_tunnel
print_usage
echo
echo "Host running. Press Ctrl+C to stop."

# Keep alive while children run
while kill -0 "$PYTHON_SERVER_PID" 2>/dev/null && kill -0 "$CLOUDFLARED_PID" 2>/dev/null; do
  sleep 2
done
echo "A background process exited unexpectedly." >&2
exit 1
