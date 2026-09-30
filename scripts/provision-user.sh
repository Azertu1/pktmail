#!/bin/sh
set -eu

: "${MAILU_API_URL:?Set MAILU_API_URL, e.g. https://mail.example.com/api/v1}"
: "${MAILU_API_TOKEN:?Set MAILU_API_TOKEN}"
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

email="${1:?Usage: provision-user.sh user@example.com [display-name] [quota-bytes]}"
displayed_name="${2:-$email}"
quota_bytes="${3:-2000000000}"

if [ -z "${MAILU_USER_PASSWORD:-}" ]; then
  printf 'Password for %s: ' "$email" >&2
  trap 'stty echo' EXIT INT TERM HUP
  stty -echo
  IFS= read -r MAILU_USER_PASSWORD
  stty echo
  trap - EXIT INT TERM HUP
  printf '\n' >&2
fi

payload="$(jq -n \
  --arg email "$email" \
  --arg password "$MAILU_USER_PASSWORD" \
  --arg displayed_name "$displayed_name" \
  --argjson quota_bytes "$quota_bytes" \
  '{
    email: $email,
    raw_password: $password,
    comment: "Provisioned by pktmail",
    quota_bytes: $quota_bytes,
    global_admin: false,
    enabled: true,
    change_pw_next_login: true,
    enable_imap: true,
    enable_pop: false,
    allow_spoofing: false,
    forward_enabled: false,
    reply_enabled: false,
    displayed_name: $displayed_name,
    spam_enabled: true,
    spam_mark_as_read: true,
    spam_threshold: 80
  }')"

curl --fail-with-body --silent --show-error \
  --request POST "${MAILU_API_URL%/}/user" \
  --header "Authorization: ${MAILU_API_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "$payload"

printf '\nMailbox %s created.\n' "$email"
