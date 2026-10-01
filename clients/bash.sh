# SFT Bash client — requires SFT_HOST (e.g. https://xxxx.trycloudflare.com)
# Load: eval "$(curl -fsSL "$SFT_HOST/clients/bash.sh")"

if [[ -z "${SFT_HOST:-}" ]]; then
  echo "SFT_HOST is not set" >&2
  return 1 2>/dev/null || exit 1
fi

sft_send() {
  local path="$1"
  if [[ -z "$path" ]]; then
    echo "usage: sft_send <path>" >&2
    return 1
  fi
  if [[ ! -f "$path" ]]; then
    echo "sft_send: file not found: $path" >&2
    return 1
  fi
  local name encoded
  name="$(basename "$path")"
  encoded="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$name")"
  curl -fsS -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$path" \
    "${SFT_HOST}/send?name=${encoded}" \
    >/dev/null
  echo "sent $name"
}

sft_receive() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "usage: sft_receive <name>" >&2
    return 1
  fi
  local base
  base="$(basename "$name")"
  curl -fsS -o "$base" "${SFT_HOST}/files/${base}"
  echo "received $base"
}
