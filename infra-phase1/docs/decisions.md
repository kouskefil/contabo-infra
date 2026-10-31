# Journal de décisions

## 2026-10-31 — Réinstallation complète sans reprise de données
- Décision : RAZ du VPS, aucune donnée conservée (GitLab, Jenkins, registry, app).
- Alternatives écartées : sauvegarde/migration GitLab et Jenkins ; mise à niveau in-place.
- Raison : repartir d'une base propre, reproductible et documentée ; code source hébergé hors VPS.

## 2026-10-31 — Ubuntu 26.04.1 LTS au lieu de 24.04
- Décision : conserver Ubuntu 26.04.1 LTS (« resolute »).
- Alternative écartée : réinstaller en 24.04.
- Raison : LTS plus récente (support plus long), version .1 disponible. Vigilance sur le support des outils tiers à chaque installation.

## 2026-10-31 — Clé SSH installée manuellement
- Constat : l'injection de clé via le panneau Contabo n'a pas abouti ; erreur bootcmd dans le cloud-init fourni par Contabo, sans impact.
- Décision : clé ~/.ssh/contabo installée via ssh-copy-id ; mot de passe root conservé uniquement pour la console VNC.

## 2026-10-31 — Utilisateur d'administration
- Décision : utilisateur `kouskefil`, groupe sudo, sudo avec mot de passe (défense en profondeur). Utilisateur par défaut `ubuntu` verrouillé (mot de passe bloqué, shell nologin), non supprimé.

## 2026-10-31 — Durcissement SSH
- Décision : clé uniquement, root interdit, AllowUsers kouskefil, MaxAuthTries 3, fichier 00-hardening.conf (préfixe 00 pour primer sur 50-cloud-init.conf).
- Port : 22 conservé. Alternative écartée : port non standard (gain de sécurité marginal, complexité ssh.socket).
- Écoute IPv4 + IPv6 conservée. Transfert de port conservé pour le tunnel PostgreSQL (Phase 4).

## 2026-10-31 — Firewall UFW
- Décision : deny incoming / allow outgoing, IPv4 + IPv6, seul 22/tcp ouvert en mode limit.
- 80/443 non ouverts avant la Phase 3. Point d'attention : Docker contourne UFW pour les ports publiés → traité en Phase 2.

## 2026-10-31 — fail2ban
- Décision : jail sshd, backend systemd, mode aggressive, ban 1h progressif (×2 par récidive, max 1 semaine), action nftables.
- Alternative écartée : IP du domicile dans ignoreip (IP dynamique).

## 2026-10-31 — Mises à jour de sécurité automatiques
- Décision : unattended-upgrades (dépôts Ubuntu security), nettoyage des anciens noyaux, reboot automatique à 04:30 même avec sessions ouvertes.
- Alternatives écartées : reboot manuel (risque d'oubli) ; Livepatch (reporté).
- Conséquence : tous les services devront redémarrer seuls (restart: unless-stopped, healthchecks, arrêt gracieux) ; reboot testé en fin de Phase 5.

## 2026-10-31 — Swap
- Décision : fichier /swapfile de 4 Go, swappiness 10.
- Raison : amortisseur contre l'OOM killer (plusieurs JVM, futur modèle d'IA), pas une extension de mémoire.

## 2026-10-31 — Fuseau horaire et NTP
- Décision : Europe/Paris ; chrony (installé par défaut) conservé.
