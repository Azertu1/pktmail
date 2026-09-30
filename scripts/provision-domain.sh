#!/bin/sh
set -eu

: "${MAILU_API_URL:?Set MAILU_API_URL, e.g. https://mail.example.com/api/v1}"
: "${MAILU_API_TOKEN:?Set MAILU_API_TOKEN}"
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

domain="${1:?Usage: provision-domain.sh example.com}"

payload="$(jq -n --arg name "$domain" '{
  name: $name,
  comment: "Provisioned by pktmail",
  max_users: 0,
  max_aliases: 0,
  max_quota_bytes: 0,
  signup_enabled: false
}')"

curl --fail-with-body --silent --show-error \
  --request POST "${MAILU_API_URL%/}/domain" \
  --header "Authorization: ${MAILU_API_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "$payload"

printf '\nDomain %s created. Generate its DKIM key in Mailu before publishing DNS records.\n' "$domain"
