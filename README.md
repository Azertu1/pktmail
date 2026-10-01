# pktmail — stack Mailu pour production

Cette stack déploie Mailu 2024.06 avec SMTP, Submission, IMAPS, Rspamd, analyse des macros, Roundcube, administration Web et API REST. Elle est conçue pour cohabiter avec `pktmfr` sur le même VPS.

`pktmfr` publie déjà son frontend sur `127.0.0.1:8080` et ne définit ni reverse proxy Docker ni réseau externe partagé. `pktmail` reste donc isolé et publie ses interfaces Web sur `127.0.0.1:8081` et `127.0.0.1:8443`. Le reverse proxy Nginx de l’hôte garde les ports publics 80/443. Les protocoles mail sont exposés directement par Mailu.

## Ports

| Port public | Service | Usage |
|---:|---|---|
| 25/tcp | SMTP | Réception entre serveurs |
| 465/tcp | Submissions | Envoi client avec TLS implicite |
| 587/tcp | Submission | Envoi client avec STARTTLS |
| 993/tcp | IMAPS | Lecture des boîtes |
| 4190/tcp | ManageSieve | Filtres côté serveur |
| 127.0.0.1:8081 | HTTP Mailu | Interne au reverse proxy |
| 127.0.0.1:8443 | HTTPS Mailu | Interne au reverse proxy |

POP3/POP3S et IMAP non chiffré ne sont volontairement pas exposés. Aucun `Dockerfile` personnalisé n’est nécessaire : les images officielles Mailu sont utilisées telles quelles.

## 1. Préparer la configuration

Sur le VPS :

```bash
git clone <URL_DU_DEPOT_PKTMAIL> /opt/pktmail
cd /opt/pktmail
cp .env .env
openssl rand -hex 16   # SECRET_KEY
openssl rand -hex 32   # API_TOKEN
chmod 600 .env
chmod +x scripts/*.sh
```

Éditer au minimum dans `.env` :

- `DOMAIN` : domaine des adresses, par exemple `example.com` ;
- `HOSTNAMES` : nom public du serveur, par exemple `mail.example.com` ;
- `SECRET_KEY`, `API_TOKEN`, `WEBSITE` et `SITENAME` ;
- `SUBNET` si `192.168.203.0/24` entre en conflit avec un réseau du VPS ;
- `BIND_ADDRESS4` avec l’IPv4 publique réellement assignée au VPS si possible.

Vérifier les réseaux existants avant de démarrer :

```bash
docker network ls
ip route
```

Créer les répertoires persistants :

```bash
mkdir -p data/{admin,certs,dkim,filter,mail,mailqueue,redis,webmail}
mkdir -p data/overrides/{dovecot,nginx,postfix,roundcube,rspamd}
```

Toutes les données persistantes sont sous `data/`, exclu de Git.

## 2. TLS et reverse proxy

La stack utilise `TLS_FLAVOR=cert` parce que les ports 80/443 sont déjà détenus par le reverse proxy de l’hôte. Mailu a néanmoins besoin du même certificat pour SMTP/IMAP.

Copier le certificat dans Mailu :

```bash
MAIL_HOSTNAME=mail.example.com MAILU_DIRECTORY=/opt/pktmail \
  sudo -E ./scripts/install-certificate.sh
```

Installer `deploy/nginx/mail.example.com.conf` dans la configuration Nginx de l’hôte, remplacer le domaine et les chemins de certificats, puis valider/recharger Nginx :

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Le script `install-certificate.sh` peut être appelé par le `--deploy-hook` de Certbot après chaque renouvellement. Ne montez pas directement les liens symboliques de `/etc/letsencrypt/live` dans le conteneur : copiez les fichiers réels comme le fait le script.

## 3. Déployer

Valider avant de créer les conteneurs :

```bash
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100
```

Créer le premier administrateur sans conserver son mot de passe dans Git :

```bash
read -rsp 'Mot de passe admin : ' ADMIN_PASSWORD; echo
docker compose exec admin flask mailu admin admin example.com "$ADMIN_PASSWORD"
unset ADMIN_PASSWORD
```

Le compte `postmaster@example.com` doit exister ou être un alias valide. On peut créer `admin@example.com`, puis ajouter l’alias `postmaster@example.com` vers celui-ci dans l’administration.

Interfaces :

- administration : `https://mail.example.com/admin/` ;
- webmail : `https://mail.example.com/webmail/` ;
- API/Swagger : `https://mail.example.com/api/` ;
- schéma OpenAPI : `https://mail.example.com/api/v1/swagger.json`.

## 4. DNS indispensable

Remplacer `203.0.113.10` par l’IPv4 publique du VPS :

```dns
mail.example.com.      3600 IN A     203.0.113.10
example.com.           3600 IN MX 10 mail.example.com.
example.com.           3600 IN TXT   "v=spf1 mx -all"
_dmarc.example.com.    3600 IN TXT   "v=DMARC1; p=quarantine; rua=mailto:postmaster@example.com; adkim=s; aspf=s"
```

Le PTR (reverse DNS) de `203.0.113.10` doit être configuré chez l’hébergeur vers `mail.example.com`, et ce nom doit revenir vers la même IP.

Pour DKIM, ajouter d’abord `example.com` dans Mailu, ouvrir les détails du domaine, cliquer sur **Regenerate keys**, puis publier exactement le TXT DKIM fourni par Mailu. Après observation des rapports DMARC, passer progressivement de `p=quarantine` à `p=reject`.

Ne placez jamais le nuage orange/proxy d’un CDN devant les enregistrements SMTP/IMAP : le nom `mail.example.com` doit résoudre directement vers le VPS.

## 5. Pare-feu et prérequis opérateur

Autoriser au minimum `25/tcp`, `465/tcp`, `587/tcp`, `993/tcp` et `4190/tcp`. Vérifier auprès de l’hébergeur que le port 25 sortant n’est pas bloqué. Le VPS doit disposer d’un DNS récursif validant DNSSEC ; le conteneur Unbound inclus remplit ce rôle.

Mailu sans ClamAV demande environ 1 Gio de RAM et 1 Gio de swap. Cette stack laisse ClamAV désactivé pour éviter sa forte consommation, tout en conservant Rspamd et oletools.

## 6. Provisionnement automatisé

Le jeton de `.env` est un secret d’administration complet. Ne l’écrivez pas dans un script ni dans les logs CI.

Créer un domaine :

```bash
export MAILU_API_URL=https://mail.example.com/api/v1
export MAILU_API_TOKEN='jeton_api_de_.env'
./scripts/provision-domain.sh example.com
```

Les scripts de provisioning utilisent `curl` et `jq` (`sudo apt install curl jq` sur Ubuntu).

Créer une boîte de 2 Gio (le mot de passe est demandé sans écho) :

```bash
./scripts/provision-user.sh alice@example.com 'Alice' 2000000000
```

Équivalent API minimal :

```bash
curl --fail-with-body \
  -H "Authorization: $MAILU_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -X POST "$MAILU_API_URL/user" \
  -d '{"email":"alice@example.com","raw_password":"CHANGE_ME","enabled":true,"enable_imap":true,"enable_pop":false,"quota_bytes":2000000000}'
```

Le jeton Mailu est envoyé brut dans l’en-tête `Authorization`, sans préfixe `Bearer`.

## 7. Vérifications avant mise en production

```bash
docker compose ps
curl -fsS -H "Authorization: $MAILU_API_TOKEN" \
  https://mail.example.com/api/v1/domain
openssl s_client -connect mail.example.com:465 -servername mail.example.com </dev/null
openssl s_client -connect mail.example.com:993 -servername mail.example.com </dev/null
```

Tester ensuite un envoi et une réception externes, vérifier que SPF/DKIM/DMARC passent, puis contrôler que le serveur n’est pas un relais ouvert. Sauvegarder régulièrement `data/` et `.env` dans un emplacement chiffré.

## Mise à jour

La branche d’images reste épinglée sur `2024.06`. Lire les notes de version avant toute montée de version :

```bash
docker compose pull
docker compose down
docker compose up -d
```

Le dépôt local n’est pas poussé automatiquement sur GitHub.
