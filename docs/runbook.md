# Runbook

## Accès au VPS
- Normal : `ssh contabo-vps` depuis le Mac (utilisateur kouskefil, clé ~/.ssh/contabo, empreinte SHA256:qtWGQ2p6FHLo8MZBRLwXX3YisGvNglJsuDQcEQytcQA), puis `sudo` pour l'administration.
- Empreinte de l'hôte (ED25519) : SHA256:w7gXKsr1gnv0lq+IfooaYhj+LspUGrORnroUjx4ryGU. Si l'alerte « REMOTE HOST IDENTIFICATION HAS CHANGED » apparaît sans réinstallation : ne pas se connecter, comparer via la console VNC.
- Secours : console VNC du panneau Contabo, root + mot de passe (gestionnaire de mots de passe). Root n'est pas accessible en SSH.

## SSH
- Config effective : `sudo sshd -T | grep -Ei 'permitrootlogin|passwordauthentication|allowusers'`
- Modifier : éditer /etc/ssh/sshd_config.d/00-hardening.conf → `sudo sshd -t` → `sudo systemctl reload ssh` → tester depuis un **nouveau** terminal en gardant l'ancien ouvert.
- Retour arrière : `sudo rm /etc/ssh/sshd_config.d/00-hardening.conf && sudo systemctl reload ssh`

## Firewall (UFW)
- État : `sudo ufw status verbose`
- Changement risqué : `sudo systemd-run --on-active=5min --unit=ufw-failsafe /usr/sbin/ufw disable` avant, puis `sudo systemctl stop ufw-failsafe.timer` une fois l'accès vérifié.
- Désactiver en urgence : `sudo ufw disable` (ou depuis la console VNC).

## fail2ban
- État : `sudo fail2ban-client status sshd`
- Débannir : `sudo fail2ban-client set sshd unbanip <IP>` (IP publique du Mac : `curl -4 ifconfig.me`).
- Logs : `sudo journalctl -u fail2ban --since today`

## Mises à jour
- Historique : /var/log/unattended-upgrades/unattended-upgrades.log
- Reboot en attente : `cat /var/run/reboot-required.pkgs`
- Derniers redémarrages : `last reboot | head -5`
- Mise à jour manuelle complète : `sudo apt update && sudo apt full-upgrade`

## Swap / mémoire
- État : `swapon --show; free -h; cat /proc/sys/vm/swappiness`
- Processus gourmands : `htop` (tri par MEM avec F6)

## Heure
- `timedatectl` ; synchronisation : `chronyc tracking`

## Docker
- État : `systemctl is-active docker` ; `docker ps` ; `docker stats --no-stream`
- Config du démon : /etc/docker/daemon.json (référence : docker/daemon.json). Modifier → `sudo dockerd --validate --config-file /etc/docker/daemon.json` → `sudo systemctl restart docker` (les conteneurs continuent grâce à live-restore).
- Retour arrière démon : `sudo mv /etc/docker/daemon.json /etc/docker/daemon.json.ko && sudo systemctl restart docker` ; logs : `sudo journalctl -u docker -n 50`
- Mise à jour de Docker : `sudo apt update && sudo apt upgrade` (non automatique).
- Ports réellement exposés : `sudo ss -tlnp | grep -v 127.0.0` (UFW ne voit pas les ports publiés par Docker).
- Espace disque : `docker system df` ; nettoyage des images inutilisées : `docker image prune`

## Stacks Compose (/srv/stacks/<stack>)
- Toujours lancer depuis le dossier de la stack (lecture du `.env` local).
- Démarrer / mettre à jour : `cd /srv/stacks/<stack> && docker compose up -d`
- Arrêter : `docker compose down` (les volumes sont conservés ; `down -v` les SUPPRIME)
- Redémarrer : `docker compose restart <service>`
- Logs : `docker compose logs -f --tail=100 <service>`
- Santé : `docker compose ps` ; détail : `docker inspect <conteneur> --format '{{json .State.Health}}' | jq`
- Valider un compose : `docker compose config --quiet`

## Déploiement depuis Git
1. Mac : modifier dans le dépôt, commit, push. Archives fournies : `unzip -o <archive>.zip` depuis la racine du dépôt (jamais de double-clic).
2. Serveur : `git -C /srv/infra pull` (fast-forward uniquement), puis `docker compose up -d` dans la stack concernée.
- `git -C /srv/infra status --short --ignored` ne doit montrer que des lignes `!!` (.env).
- Annuler une modification locale accidentelle : `git -C /srv/infra checkout -- <fichier>`
- Récupérer un fichier tel qu'il était dans un commit : `git show <commit>:<chemin> > <chemin>`
- ⚠️ Ne jamais lancer `git clean -fdx` dans /srv/infra : supprime tous les `.env`.
- Deploy key : ~/.ssh/github_infra_deploy (kouskefil), alias `github-infra`, lecture seule. Test : `ssh -T github-infra`.
- ⚠️ Règle générale des montages : un fichier monté **seul** (Caddyfile, prometheus.yml, config.alloy…) est remplacé par `git pull`, et le conteneur continue de voir l'ancien jusqu'à sa recréation. Un dossier monté (rules/, grafana/provisioning/) n'a pas ce problème.

## Reverse proxy Caddy (/srv/stacks/proxy)
- État : `cd /srv/stacks/proxy && docker compose ps` ; version : `docker compose exec caddy caddy version`
- Logs : `docker compose logs -f --tail=100 caddy` ; certificats : `docker compose logs caddy | grep -iE 'certificate|error'`
- Appliquer un Caddyfile modifié (après git pull) : `docker compose restart caddy` (coupure d'une à deux secondes), puis vérifier que le conteneur voit la nouvelle version : `docker compose exec caddy grep -c '<nom>.kouskefil.tech' /etc/caddy/Caddyfile`.
- ⚠️ `caddy reload` seul ne suffit pas après un `git pull` : le Caddyfile est monté comme fichier unique, git le remplace par un nouveau fichier, et le conteneur continue de voir l'ancien jusqu'à son redémarrage.
- Valider avant rechargement : `docker compose exec -w /etc/caddy caddy caddy validate`
- Changer de version : `docker pull caddy:<version>-alpine` pour vérifier le tag, modifier l'image dans compose.yaml (commit), puis `docker compose up -d`.
- ⚠️ Ne jamais `docker compose down -v` sur cette stack : le volume caddy_data contient certificats et compte ACME (limites Let's Encrypt).
- Échec de certificat : vérifier DNS (`dig +short @dns200.anycast.me <nom> A`), port 80 joignable, CAA. Ne pas redémarrer Caddy en boucle.
- Contrôle externe : SSL Labs (ssllabs.com/ssltest) et securityheaders.com. Surveillance continue : la règle `CertificatBientotExpire` (voir Supervision).

## Exposer un nouveau service
1. DNS OVH : enregistrement A `<nom>` → 75.119.129.90 ; vérifier avec dig.
2. Stack de l'application : aucun `ports:` ; réseau `proxy` (external) avec alias unique `<stack>-<service>`.
3. Caddyfile : bloc `<nom>.kouskefil.tech { import security_headers ; encode zstd gzip ; reverse_proxy <alias>:<port> }`.
4. Commit/push, `git pull` sur le serveur, `docker compose up -d` de l'application, puis `docker compose restart caddy` dans /srv/stacks/proxy.
5. Vérifier : `curl -sI https://<nom>.kouskefil.tech`.
6. Ajouter une sonde : voir « Ajouter une sonde HTTP » dans la section Supervision.
- 502 Bad Gateway : `docker network inspect proxy --format '{{range .Containers}}{{.Name}} {{end}}'`

## Réseau Docker partagé
- `proxy` : créé une fois avec `docker network create proxy` (à recréer après une réinstallation, avant toute stack).

## PostgreSQL (/srv/stacks/postgres)
- État : `docker compose ps` ; version : `docker compose exec postgres psql -U postgres -tAc "SELECT version();"`
- Console admin : `docker compose exec postgres psql -U postgres` ; depuis le Mac : tunnel SSH vers 127.0.0.1:5432.
- Logs : `docker compose logs -f --tail=100 postgres` (requêtes > 500 ms journalisées)
- Mise à jour mineure : `docker pull postgres:<version>-trixie`, changer le tag dans compose.yaml (commit), `docker compose up -d` (coupure de quelques secondes).
- Changer un mot de passe : `ALTER ROLE <role> PASSWORD '...'` dans psql, puis mettre à jour le fichier secret correspondant. Modifier secrets/postgres_password n'a aucun effet après l'initialisation.
- ⚠️ Jamais `docker compose down -v` : supprime le volume postgres_data.

## Nouvelle application avec base de données
1. `cd /srv/stacks/postgres && ./scripts/create-app-db.sh <app>`
2. Mot de passe : /srv/stacks/<app>/secrets/db_password (à monter en secret Compose dans la stack de l'application).
3. Stack de l'application : réseau `db` (external), connexion à `postgres:5432`, base et utilisateur `<app>`.

## Sauvegardes PostgreSQL
- Automatique : timer `pg-backup.timer` à 02:30 → /srv/backups/postgres/<AAAA-MM-JJ_HHMM>/ (7 conservées).
- État : `systemctl list-timers pg-backup.timer` ; échecs : `systemctl --failed` ; logs : `journalctl -u pg-backup.service -n 20`
- Sauvegarde manuelle (avant une opération risquée) : `/srv/infra/stacks/postgres/scripts/backup.sh`
- Intégrité : `cd /srv/backups/postgres/<dossier> && sha256sum -c SHA256SUMS`
- Modifier le timer : éditer systemd/ dans Git, puis `sudo cp /srv/infra/systemd/pg-backup.* /etc/systemd/system/ && sudo systemctl daemon-reload`
- Surveillance : le script écrit /srv/metrics/pg_backup.prom, lu par node-exporter. Contrôle rapide :
  `curl -s --data-urlencode 'query=pg_backup_last_run_success' http://127.0.0.1:9090/api/v1/query | jq -r '.data.result[0].value[1]'` → `1`
- Si la requête ne renvoie rien : vérifier que /srv/metrics existe et appartient à kouskefil, et que node-exporter monte bien `/srv/metrics:/textfile:ro`.

## Restaurer une base
Variables : `LATEST=$(ls -1d /srv/backups/postgres/20* | tail -1)`, depuis /srv/stacks/postgres.
- **Vérifier sans risque** (base séparée) :
  `docker compose exec -T postgres psql -U postgres -c "CREATE DATABASE <app>_restore_test;"`
  `docker compose exec -T postgres pg_restore -U postgres -d <app>_restore_test --exit-on-error < "$LATEST/<app>.dump"`
- **Remplacer une base endommagée** ⚠️ (faire d'abord une sauvegarde manuelle de l'état endommagé) :
  `docker compose exec -T postgres psql -U postgres -c "DROP DATABASE <app> WITH (FORCE);"`
  `docker compose exec -T postgres pg_restore -U postgres -C -d postgres --exit-on-error < "$LATEST/<app>.dump"`
  → recrée la base avec son propriétaire et ses droits.
- **Serveur neuf** : restaurer d'abord les rôles (`docker compose exec -T postgres psql -U postgres < "$LATEST/globals.sql"`), puis chaque base avec `pg_restore -C`.
- Vérifier : comparer `SELECT count(*)` et les droits (`SELECT datacl FROM pg_database WHERE datname='<app>'`).

## Application clients-ws (SOAP) — /srv/stacks/clients, code dans /srv/apps/clients-ws
- État : `cd /srv/stacks/clients && docker compose ps` ; logs : `docker compose logs -f --tail=100 app`
- Public : https://api.kouskefil.tech/ws (WSDL : /ws/clients.wsdl) ; local : http://127.0.0.1:8085/ws
- Authentification : WS-Security UsernameToken, compte `partenaire`, mot de passe dans /srv/stacks/clients/secrets/ws_password.
- Appels de test (sur le VPS, où se trouve le secret) : `cd /srv/apps/clients-ws && samples/call.py samples/<requete>.xml` ; options `--url https://api.kouskefil.tech/ws`, `--no-auth`, `--wrong-password`, `--replay`, `--show-request`.
- Changer le mot de passe WS-Security : réécrire secrets/ws_password (sans retour à la ligne), puis `docker compose up -d --force-recreate`.
- Fault « A replay attack has been detected » : message déjà reçu (comportement voulu) ; « The security token could not be authenticated » : identifiant ou mot de passe faux, ou horloge du client décalée de plus de 5 minutes.
- Depuis le Mac (SoapUI) : importer https://api.kouskefil.tech/ws/clients.wsdl, puis ajouter un WS-Security UsernameToken (PasswordDigest) avec le compte `partenaire`.
- Mettre à jour le code : `git -C /srv/apps/clients-ws pull`, puis `cd /srv/stacks/clients && docker compose build && docker compose up -d`
- Santé détaillée : `docker inspect clients-app-1 --format '{{json .State.Health}}' | jq '.Log[-1]'`
- Un SOAP Fault renvoie toujours HTTP 500 (SOAP 1.1) : lire le `faultcode` (Client = requête en cause, Server = service en cause).
- `.env` de la stack : APP_UID / APP_GID = `id -u` / `id -g` de kouskefil (lecture du secret).

## Nouvelle application construite sur le VPS
1. Dépôt de l'application sur GitHub ; sur le VPS : deploy key dédiée (`~/.ssh/github_<app>_deploy`), alias SSH `github-<app>`, clone dans /srv/apps/<app> avec `pull.ff only`.
2. Base : `create-app-db.sh <app>` (voir « Nouvelle application avec base de données »).
3. Stack dans contabo-infra : `build.context: /srv/apps/<app>`, secret `db_password`, réseau `db`, `user: ${APP_UID}:${APP_GID}`.

## Application taches-api (FastAPI) — /srv/stacks/taches, code dans /srv/apps/taches-api
- État : `cd /srv/stacks/taches && docker compose ps` ; logs : `docker compose logs -f --tail=100 app`
- Public : https://api.kouskefil.tech/taches ; local : http://127.0.0.1:8086 (documentation interactive : /docs, par tunnel `ssh -N -L 8086:127.0.0.1:8086 contabo-vps`)
- Authentification : en-tête `X-API-Key`, clé dans /srv/stacks/taches/secrets/api_key.
- Test complet (sur le VPS) : `cd /srv/apps/taches-api && samples/demo.sh` (ou `samples/demo.sh https://api.kouskefil.tech`) ; codes attendus : 201, 200, 200, 200, 204, 404, 422, 401.
- Santé : `curl -s http://127.0.0.1:8086/healthz/ready`
- Mettre à jour : `git -C /srv/apps/taches-api pull`, puis `cd /srv/stacks/taches && docker compose build && docker compose up -d`
- Changer la clé d'API : réécrire secrets/api_key (sans retour à la ligne), puis `docker compose up -d --force-recreate`.

## Déployer, mettre à jour ou retirer une application
- Procédure complète : docs/deploiement-application.md.
- Valider le Caddyfile avant de redémarrer Caddy : `docker run --rm -v /srv/stacks/proxy/Caddyfile:/etc/caddy/Caddyfile:ro caddy:2.11.7-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile`
- Retour arrière rapide : `docker tag <depot>:precedent <depot>:local`, puis `docker compose up -d --force-recreate` (suppose un `docker tag <depot>:local <depot>:precedent` avant la mise à jour).

## Supervision (/srv/stacks/monitoring)
Huit services : prometheus (métriques), grafana (tableaux de bord), loki (logs), alloy (collecte des logs), alertmanager (notifications Telegram), node-exporter (machine), cadvisor (conteneurs), blackbox (sondes HTTP).

### Accès aux interfaces — tunnel SSH, depuis le Mac
- Grafana : `ssh -N -L 3000:127.0.0.1:3000 contabo-vps` puis http://localhost:3000 (compte `admin`, mot de passe dans le gestionnaire).
- Prometheus : `ssh -N -L 9090:127.0.0.1:9090 contabo-vps` puis http://localhost:9090 (onglets Status → Targets, et Alerts).
- Alertmanager n'a pas de port publié : passer par `docker compose exec` (voir « Silencer une alerte »).
- Aucune de ces interfaces n'est accessible depuis Internet — c'est voulu.

### Contrôles de routine
- Toutes les cibles scrutées :
  `curl -s http://127.0.0.1:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job) \(.health)"' | sort`
  → toutes les lignes en `up`.
- Règles chargées :
  `curl -s http://127.0.0.1:9090/api/v1/rules | jq -r '.data.groups[] | "\(.name) : \(.rules|length) règles"'`
  → machine 6, conteneurs 2, sauvegardes 3, sondes 3.
- Alertes en cours :
  `curl -s http://127.0.0.1:9090/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname) [\(.state)] \(.labels.instance // "")"'`
  → l'état passe par `pending` (condition vraie, délai `for:` non écoulé) puis `firing` (Alertmanager prend le relais).
- Sondes HTTP :
  `curl -s --data-urlencode 'query=probe_success' http://127.0.0.1:9090/api/v1/query | jq -r '.data.result[] | "\(.metric.instance) → \(.value[1])"'`
  → trois lignes à `1`.
- Certificats, en jours restants :
  `curl -s --data-urlencode 'query=(probe_ssl_earliest_cert_expiry - time()) / 86400' http://127.0.0.1:9090/api/v1/query | jq -r '.data.result[] | "\(.metric.instance) → \(.value[1] | tonumber | floor) jours"'`

### Appliquer une modification de configuration
- **Règles** (`rules/*.yml`) : le dossier est monté → `git pull` puis rechargement à chaud, sans coupure :
  `curl -X POST http://127.0.0.1:9090/-/reload`
- **prometheus.yml** : monté comme fichier unique → `docker compose up -d --force-recreate prometheus`.
- Même chose pour `alloy/config.alloy`, `loki/config.yaml`, `alertmanager/config.yml`, `blackbox/blackbox.yml` : recréer le service concerné.
- Valider une règle avant de la charger :
  `docker compose exec prometheus promtool check rules /etc/prometheus/rules/sondes.yml`

### Interroger un service sans port publié
`docker run --rm --network monitoring_monitoring curlimages/curl:latest -s http://loki:3100/ready`
(remplacer par `blackbox:9115/metrics`, `alertmanager:9093/-/healthy`, `alloy:12345/metrics`…)

### Silencer une alerte (maintenance prévue)
- Créer : `docker compose exec alertmanager amtool --alertmanager.url=http://localhost:9093 silence add alertname=SondeHttpEnEchec --duration=2h --comment="maintenance"`
- Lister : `... amtool --alertmanager.url=http://localhost:9093 silence query`
- Lever : `... silence expire <id>`

### Logs (Loki)
- Par Grafana → Explore → source Loki. Exemples LogQL :
  - `{stack="clients"}` — tous les logs de la stack clients
  - `{conteneur="postgres"} |= "ERROR"`
  - `{stack="proxy"} |= "certificate"`
- Étiquettes disponibles : `conteneur`, `stack`, `service`, `job="docker"`. Le reste se filtre au moment de la requête (`|=`, `!=`, `|~`).
- Rétention : 14 jours.
- Erreurs « timestamp too old » au premier démarrage d'Alloy : normal, rattrapage de logs antérieurs à la fenêtre de rétention ; cela cesse seul.

### Mettre à jour une image de la stack
1. Vérifier que le tag existe : `docker manifest inspect <image>:<tag> > /dev/null && echo TAG_OK`
2. Modifier le tag dans compose.yaml (sur le Mac), commit, push.
3. `git -C /srv/infra pull && cd /srv/stacks/monitoring && docker compose up -d <service>`
- Ne jamais utiliser de tag flottant (`latest`, `v0`, `master`).
- ⚠️ Ne jamais `docker compose down -v` : supprime l'historique des métriques (prometheus_data), les tableaux de bord (grafana_data) et les logs (loki_data).

### Ajouter une sonde HTTP
1. Dans `stacks/monitoring/prometheus.yml`, ajouter l'URL aux `targets:` du job `sondes-publiques` (2xx attendu) ou `sondes-protegees` (401 attendu).
2. Pour un autre code attendu : ajouter un module dans `blackbox/blackbox.yml` (`valid_status_codes: [...]`), puis un job qui l'utilise.
3. `git pull` sur le serveur, puis `docker compose up -d --force-recreate prometheus`.
4. Vérifier avec la requête `probe_success` ci-dessus.

### Tester la chaîne d'alerte de bout en bout
`cd /srv/stacks/demo && docker compose stop` → attendre 6 à 7 minutes (la règle est en `for: 5m`) → message Telegram « PROBLÈME » → `docker compose up -d` → message « RÉSOLU ».
- ⚠️ Un test de panne doit durer au moins deux fois le délai de détection, sinon il ne prouve rien.
- Pendant ce test, api.kouskefil.tech reste en ligne (seule la stack demo est arrêtée).

### Panne de la surveillance elle-même
- Un conteneur `unhealthy` dans cette stack bloque les services qui en dépendent (`depends_on`). Loki n'a volontairement pas de healthcheck : son image ne contient ni `wget` ni `curl`.
- Si Alertmanager est arrêté, Prometheus continue d'évaluer les règles mais plus rien n'est notifié. La règle `CibleInjoignable` couvre ce cas… à condition qu'Alertmanager soit vivant pour l'envoyer : la seule vraie parade est une sonde externe (point ouvert).

## Après un redémarrage du serveur
- Rien à faire : tout redémarre seul (testé le 2026-11-15). Contrôle : `uptime && docker ps --format 'table {{.Names}}\t{{.Status}}'`
- Relances d'un conteneur : `docker inspect --format '{{.Name}} {{.RestartCount}}' $(docker ps -q)`
