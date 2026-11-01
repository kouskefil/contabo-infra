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
