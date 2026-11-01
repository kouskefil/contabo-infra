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
1. Mac : modifier dans le dépôt, commit, push.
2. Serveur : `git -C /srv/infra pull` (fast-forward uniquement), puis `docker compose up -d` dans la stack concernée.
- `git -C /srv/infra status --short --ignored` ne doit montrer que des lignes `!!` (.env).
- Annuler une modification locale accidentelle : `git -C /srv/infra checkout -- <fichier>`
- ⚠️ Ne jamais lancer `git clean -fdx` dans /srv/infra : supprime tous les `.env`.
- Deploy key : ~/.ssh/github_infra_deploy (kouskefil), alias `github-infra`, lecture seule. Test : `ssh -T github-infra`.
