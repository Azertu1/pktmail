#!/bin/sh
set -eu

: "${MAIL_HOSTNAME:?Set MAIL_HOSTNAME, e.g. mail.example.com}"
MAILU_DIRECTORY="${MAILU_DIRECTORY:-/opt/pktmail}"
CERTBOT_DIRECTORY="${CERTBOT_DIRECTORY:-/etc/letsencrypt}"

install -d -m 0750 "${MAILU_DIRECTORY}/data/certs"
install -m 0644 "${CERTBOT_DIRECTORY}/live/${MAIL_HOSTNAME}/fullchain.pem" \
  "${MAILU_DIRECTORY}/data/certs/cert.pem"
install -m 0640 "${CERTBOT_DIRECTORY}/live/${MAIL_HOSTNAME}/privkey.pem" \
  "${MAILU_DIRECTORY}/data/certs/key.pem"

cd "$MAILU_DIRECTORY"
if docker compose ps --status running -q front | grep -q .; then
  docker compose exec -T front nginx -s reload
  docker compose exec -T front doveadm reload
fi
