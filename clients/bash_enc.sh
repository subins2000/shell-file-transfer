# SFT Bash client (encrypted wire) — requires SFT_HOST and SFT_KEY
# Load: eval "$(curl -fsSL "$SFT_HOST/clients/bash_enc.sh")"

if [[ -z "${SFT_HOST:-}" ]]; then
  echo "SFT_HOST is not set" >&2
  return 1 2>/dev/null || exit 1
fi
if [[ -z "${SFT_KEY:-}" ]]; then
  echo "SFT_KEY is not set" >&2
  return 1 2>/dev/null || exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required for encrypted transfer" >&2
  return 1 2>/dev/null || exit 1
fi

sft_urlencode() {
  local LC_ALL=C s="$1" i c out=
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) printf -v c '%%%02X' "'$c"; out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

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
  encoded="$(sft_urlencode "$name")"
  openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -pass env:SFT_KEY -in "$path" \
    | curl -fsS -X POST \
      -H "Content-Type: application/octet-stream" \
      --data-binary @- \
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
  curl -fsS "${SFT_HOST}/files/$(sft_urlencode "$base")" \
    | openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass env:SFT_KEY -out "$base"
  echo "received $base"
}
