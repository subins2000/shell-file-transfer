#!/usr/bin/env bash

# Copyright (C) 2026 Subin Siby <mail@subinsb.com>
# License: AGPL-3.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PORT="${SFT_PORT:-8090}"
ENCRYPT=0
TUNNEL_SERVICE=cloudflare
PYTHON_SERVER_PID=""
TUNNEL_PID=""
TUNNEL_LOG="$(mktemp "${TMPDIR:-/tmp}/sft-tunnel.XXXXXX")"

usage() {
  cat <<EOF
Usage: ./host.sh [--encrypt] [--tunnel-service cloudflare|localhostrun]

  --encrypt                 Encrypt file bodies on the wire (generates SFT_KEY)
  --tunnel-service NAME     Tunnel backend (default: cloudflare)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --encrypt) ENCRYPT=1; shift ;;
    --tunnel-service)
      TUNNEL_SERVICE="${2:-}"
      if [[ -z "$TUNNEL_SERVICE" ]]; then
        echo "--tunnel-service requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --tunnel-service=*)
      TUNNEL_SERVICE="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$TUNNEL_SERVICE" in
  cloudflare|localhostrun) ;;
  *)
    echo "Unsupported --tunnel-service: $TUNNEL_SERVICE (use cloudflare or localhostrun)" >&2
    exit 1
    ;;
esac

cleanup() {
  set +e
  if [[ -n "${TUNNEL_PID}" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
    kill "$TUNNEL_PID" 2>/dev/null
    wait "$TUNNEL_PID" 2>/dev/null
  fi
  if [[ -n "${PYTHON_SERVER_PID}" ]] && kill -0 "$PYTHON_SERVER_PID" 2>/dev/null; then
    kill "$PYTHON_SERVER_PID" 2>/dev/null
    wait "$PYTHON_SERVER_PID" 2>/dev/null
  fi
  rm -f "$TUNNEL_LOG"
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

wait_for_tunnel_url() {
  local pattern="$1"
  local label="$2"
  TUNNEL_URL=""
  for _ in $(seq 1 30); do
    TUNNEL_URL="$(grep -m1 -oE "$pattern" "$TUNNEL_LOG" || true)"
    if [[ -n "$TUNNEL_URL" ]]; then
      export TUNNEL_URL
      return 0
    fi
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  echo "Tunnel URL not found after waiting ($label). Log:" >&2
  cat "$TUNNEL_LOG" >&2
  exit 1
}

start_tunnel_cloudflare() {
  need cloudflared
  cloudflared tunnel --url "http://localhost:${PORT}" --no-autoupdate \
    >"$TUNNEL_LOG" 2>&1 &
  TUNNEL_PID=$!
  wait_for_tunnel_url 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "cloudflare"
}

start_tunnel_localhostrun() {
  need ssh
  # nokey@ = free tunnel without SSH key/password prompts.
  # Do not use -N: localhost.run prints the public URL in the remote session.
  ssh -T \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 \
    -o ExitOnForwardFailure=yes \
    -R "80:localhost:${PORT}" \
    nokey@localhost.run \
    < /dev/null \
    >"$TUNNEL_LOG" 2>&1 &
  TUNNEL_PID=$!
  wait_for_tunnel_url 'https://[a-zA-Z0-9.-]+\.(lhr\.life|lhr\.rocks)' "localhostrun"
}

start_tunnel() {
  echo "Starting tunnel ($TUNNEL_SERVICE)..."
  case "$TUNNEL_SERVICE" in
    cloudflare) start_tunnel_cloudflare ;;
    localhostrun) start_tunnel_localhostrun ;;
  esac
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
while kill -0 "$PYTHON_SERVER_PID" 2>/dev/null && kill -0 "$TUNNEL_PID" 2>/dev/null; do
  sleep 2
done
echo "A background process exited unexpectedly." >&2
exit 1
