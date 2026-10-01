# pktmail — Mailu déployé depuis GitHub avec Portainer

Stack Docker Standalone pour mail.pktm.fr : SMTP 25, Submission 465/587, IMAPS 993,
ManageSieve 4190, Roundcube, API, Rspamd, oletools et Unbound.
Aucun Dockerfile personnalisé : images officielles de la branche stable 2024.06.
ClamAV est désactivé ; prévoir au moins 1 Gio RAM + swap, davantage selon le nombre de boîtes.

## Architecture vérifiée
Le VPS a une adresse privée 10.0.0.184 derrière NAT. La publication utilise 0.0.0.0,
jamais l'adresse publique 88.96.39.248 qui n'existe pas sur ses interfaces.
Le Nginx de l'hôte conserve 80/443. pktmfr utilise 127.0.0.1:8080.
Mailu expose le Web uniquement sur 127.0.0.1:8081 et 8443.

Les données sont toujours sous /opt/pktmail/data sur l'hôte Docker.
Elles ne dépendent ni du clone Git de Portainer ni du commit déployé.
Ne jamais utiliser ./data dans une stack Git Portainer.
Aucun réseau de pktmfr n'est partagé. Le réseau principal est 192.168.203.0/24,
Unbound est en .254 et la passerelle du proxy hôte en .1.

## Installation initiale sur le VPS
Certificat Let's Encrypt valide pour mail.pktm.fr et Nginx fonctionnel requis.
Git ne peut pas créer à lui seul le DNS, les ouvertures réseau du fournisseur ou
les certificats de l'hôte. Cette préparation est faite une fois, les mises à jour
ultérieures se font automatiquement depuis Portainer.

```bash
git clone https://github.com/Azertu1/pktmail /opt/pktmail
cd /opt/pktmail
sudo bash scripts/bootstrap-portainer.sh
sudo cp deploy/nginx/mail.pktm.fr.conf /etc/nginx/sites-available/mail.pktm.fr
# Activer ce site uniquement si le lien n'existe pas déjà :
sudo ln -s /etc/nginx/sites-available/mail.pktm.fr /etc/nginx/sites-enabled/mail.pktm.fr
sudo nginx -t && sudo systemctl reload nginx
```

Le bootstrap génère des secrets aléatoires une seule fois et copie les certificats.
Dans cette installation Portainer utilise le volume portainer_data monté en /data.
Les secrets sont dans /data/pktmail/secrets.env **vu depuis Portainer**.
Une copie protégée pour les commandes locales est dans /opt/pktmail/config/secrets.env.
Le dépôt contient uniquement mailu.env (configuration publique). Ne jamais committer
.env, secrets.env, clés privées, mots de passe ou données des boîtes.

## Stack Portainer Git
Nom : pktmail. Dépôt : https://github.com/Azertu1/pktmail.
Référence : refs/heads/main. Fichier : docker-compose.yml.
Activer le polling selon le besoin (installation actuelle : 60 secondes).
Aucune variable Portainer n'est requise pour cette installation. Supprimer les anciens
overrides BIND_ADDRESS4 ou MAILU_DATA_ROOT s'ils contredisent les valeurs ci-dessus.
Pull and redeploy applique le dernier commit. Le certificat et les données persistent.
Si Portainer est déplacé, sauvegarder/restaurer son volume et /opt/pktmail.

Pour vérifier depuis le shell de l'hôte (le chemin du fichier secret y est différent) :
```bash
cd /opt/pktmail
sudo env MAILU_SECRETS_FILE=/opt/pktmail/config/secrets.env docker compose -p pktmail config --quiet
```
Ne pas afficher le résultat complet de compose config : il contient les secrets.
Laisser Portainer gérer les déploiements, ne pas lancer une seconde stack au shell.

## TLS
TLS_FLAVOR=cert : /opt/pktmail/data/certs/cert.pem contient fullchain.pem,
key.pem contient privkey.pem. Ne pas y copier les liens symboliques Let's Encrypt.
Le hook /etc/letsencrypt/renewal-hooks/deploy/pktmail.sh copie chaque renouvellement,
recharge le frontal Mailu et Nginx sans dépendre du clone Git Portainer.
```bash
sudo bash scripts/install-certificate.sh
sudo certbot renew --dry-run
```

## Administration
https://mail.pktm.fr/admin/ ; Webmail : /webmail/ ; Swagger : /api/.
Créer le premier compte depuis le serveur (remplacer le nom seulement si nécessaire) :
```bash
read -rsp 'Mot de passe administrateur : ' MAIL_ADMIN_PASSWORD; echo
sudo docker exec pktmail-admin-1 flask mailu admin admin pktm.fr "$MAIL_ADMIN_PASSWORD"
unset MAIL_ADMIN_PASSWORD
sudo docker exec pktmail-admin-1 flask mailu alias postmaster pktm.fr admin@pktm.fr
```
Ne pas recréer un compte qui existe. Les mots de passe publiés auparavant doivent être
remplacés, y compris ailleurs s'ils ont été réutilisés.

## API et provisioning
Le jeton d'administration doit rester côté serveur. Il est envoyé tel quel dans
Authorization (pas de préfixe ajouté). Ne pas l'utiliser dans du JavaScript navigateur.
```bash
export MAILU_API_URL=https://mail.pktm.fr/api/v1
read -rsp 'Jeton API : ' MAILU_API_TOKEN; echo
export MAILU_API_TOKEN
bash scripts/provision-domain.sh autre-domaine.fr
bash scripts/provision-user.sh alice@pktm.fr 'Alice' 2000000000
unset MAILU_API_TOKEN
```
Prérequis : curl et jq. Le domaine pktm.fr doit déjà exister ; ne pas tenter de le créer
deux fois. Les scripts POST signalent les erreurs et ne remplacent pas un compte existant.
Le contrat exact de l'API installée se trouve à /api/v1/swagger.json.
Un alias donne plusieurs adresses à une même boîte ; une nouvelle boîte a ses propres
identifiants. RELAYNETS reste vide : les applications s'authentifient sur 465 ou 587.

## DNS
Publier chez le gestionnaire DNS (ne pas remplacer un SPF existant sans le fusionner) :
```dns
mail.pktm.fr.  IN A 88.96.39.248
pktm.fr.      IN MX 10 mail.pktm.fr.
pktm.fr.      IN TXT "v=spf1 mx -all"
_dmarc.pktm.fr. IN TXT "v=DMARC1; p=none; rua=mailto:postmaster@pktm.fr"
```
Dans Mailu > domaine pktm.fr > détails, générer les clés DKIM puis publier exactement
le nom et le TXT indiqués. Ne pas régénérer inutilement les clés déjà publiées.
Configurer chez l'hébergeur le PTR de 88.96.39.248 vers mail.pktm.fr.
Passer DMARC à quarantine puis reject après vérification des expéditeurs légitimes.
Ne pas publier d'AAAA sans IPv6 mail fonctionnel. Aucun proxy CDN sur le nom mail.

## Réseau et validation
Autoriser 25, 465, 587, 993 et éventuellement 4190/TCP dans les règles de l'hébergeur.
80/443 servent l'interface Web et la validation ACME. Vérifier la sortie TCP/25
auprès du fournisseur (souvent bloquée sur les VPS). Unbound nécessite DNS sortant
UDP/TCP 53. Préserver l'IP source des clients SMTP et vérifier l'absence de relais ouvert.
```bash
sudo docker ps --filter label=com.docker.compose.project=pktmail
openssl s_client -connect mail.pktm.fr:465 -servername mail.pktm.fr </dev/null
openssl s_client -starttls smtp -connect mail.pktm.fr:587 -servername mail.pktm.fr </dev/null
openssl s_client -connect mail.pktm.fr:993 -servername mail.pktm.fr </dev/null
```
Tester envoi/réception avec une boîte externe et vérifier SPF, DKIM et DMARC.
Des conteneurs healthy ne prouvent pas la délivrabilité.

## Sauvegardes et mises à jour
Sauvegarder de manière cohérente /opt/pktmail/data, config/secrets.env,
les certificats Let's Encrypt et le volume Portainer, dans un stockage chiffré.
Arrêter temporairement la stack pour une copie cohérente des bases SQLite et du courrier,
ou utiliser une méthode de snapshot cohérente. Tester la restauration.
Lire les notes Mailu avant de changer MAILU_VERSION. Ne pas supprimer les volumes
ou les dossiers de données lors d'un redéploiement.

Sources : https://mailu.io/2024.06/compose/setup.html ,
https://mailu.io/2024.06/api.html , https://mailu.io/2024.06/configuration.html .
