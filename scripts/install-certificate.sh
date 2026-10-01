#!/bin/sh
set -eu
MAIL_HOSTNAME="${MAIL_HOSTNAME:-mail.pktm.fr}"
MAILU_DATA_ROOT="${MAILU_DATA_ROOT:-/opt/pktmail/data}"
LINEAGE="/etc/letsencrypt/live/$MAIL_HOSTNAME"
if [ -n "${RENEWED_LINEAGE:-}" ] && [ "$RENEWED_LINEAGE" != "$LINEAGE" ]; then exit 0; fi
openssl x509 -in "$LINEAGE/fullchain.pem" -noout -checkhost "$MAIL_HOSTNAME" >/dev/null
install -d -m 0750 "$MAILU_DATA_ROOT/certs"
install -m 0644 "$LINEAGE/fullchain.pem" "$MAILU_DATA_ROOT/certs/cert.pem"
install -m 0600 "$LINEAGE/privkey.pem" "$MAILU_DATA_ROOT/certs/key.pem"
for container in $(docker ps -q --filter label=com.docker.compose.project=pktmail --filter label=com.docker.compose.service=front); do
  docker exec "$container" nginx -t
  docker exec "$container" nginx -s reload
  docker exec "$container" doveadm reload
done
nginx -t
systemctl reload nginx
