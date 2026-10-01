#!/bin/bash
# Run once as root on the Docker endpoint before the first Git deployment.
set -euo pipefail
cd "$(dirname "$0")/.."
portainer_data=$(docker inspect portainer --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}')
test -n "$portainer_data"
install -d -m 0700 "$portainer_data/pktmail" /opt/pktmail/config
install -d -m 0750 /opt/pktmail/data
for directory in admin certs dkim filter mail mailqueue redis webmail overrides/nginx overrides/dovecot overrides/postfix overrides/rspamd overrides/roundcube; do
  mkdir -p "/opt/pktmail/data/$directory"
done
if [ ! -f "$portainer_data/pktmail/secrets.env" ]; then
  umask 077
  {
    printf 'SECRET_KEY=%s\n' "$(openssl rand -hex 16)"
    printf 'API_TOKEN=%s\n' "$(openssl rand -hex 32)"
  } > "$portainer_data/pktmail/secrets.env"
fi
install -m 0600 "$portainer_data/pktmail/secrets.env" /opt/pktmail/config/secrets.env
bash scripts/install-certificate.sh
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
install -m 0750 scripts/install-certificate.sh /etc/letsencrypt/renewal-hooks/deploy/pktmail.sh
printf 'Ready for Git deployment in Portainer. Secrets stay on the server.\n'
