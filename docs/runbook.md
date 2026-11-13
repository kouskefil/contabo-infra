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

## Reverse proxy Caddy (/srv/stacks/proxy)
- État : `cd /srv/stacks/proxy && docker compose ps` ; version : `docker compose exec caddy caddy version`
- Logs : `docker compose logs -f --tail=100 caddy` ; certificats : `docker compose logs caddy | grep -iE 'certificate|error'`
- Recharger le Caddyfile sans coupure (après git pull) : `docker compose exec -w /etc/caddy caddy caddy reload`
- Valider avant rechargement : `docker compose exec -w /etc/caddy caddy caddy validate`
- Changer de version : `docker pull caddy:<version>-alpine` pour vérifier le tag, modifier l'image dans compose.yaml (commit), puis `docker compose up -d`.
- ⚠️ Ne jamais `docker compose down -v` sur cette stack : le volume caddy_data contient certificats et compte ACME (limites Let's Encrypt).
- Échec de certificat : vérifier DNS (`dig +short @dns200.anycast.me <nom> A`), port 80 joignable, CAA. Ne pas redémarrer Caddy en boucle.
- Contrôle externe : SSL Labs (ssllabs.com/ssltest) et securityheaders.com.

## Exposer un nouveau service
1. DNS OVH : enregistrement A `<nom>` → 75.119.129.90 ; vérifier avec dig.
2. Stack de l'application : aucun `ports:` ; réseau `proxy` (external) avec alias unique `<stack>-<service>`.
3. Caddyfile : bloc `<nom>.kouskefil.tech { import security_headers ; encode zstd gzip ; reverse_proxy <alias>:<port> }`.
4. Commit/push, `git pull` sur le serveur, `docker compose up -d` de l'application, puis `caddy reload`.
5. Vérifier : `curl -sI https://<nom>.kouskefil.tech`.
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
