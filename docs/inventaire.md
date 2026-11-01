# Inventaire — mis à jour le 2026-11-01 (fin de Phase 2)

## Serveur
| Élément | Valeur |
|---|---|
| Fournisseur | Contabo, Cloud VPS 30 SSD |
| OS | Ubuntu 26.04.1 LTS (resolute), noyau 7.0.0-42-generic |
| Ressources | 8 vCPU / 23 Go RAM / 387 Go disque (ext4) |
| IPv4 | 75.119.129.90/19 |
| IPv6 | 2a02:c207:2285:2105::1/64 |
| Fuseau | Europe/Paris, NTP via chrony |
| Swap | /swapfile 4 Go, swappiness 10 |

## Comptes
| Compte | Rôle | Accès |
|---|---|---|
| kouskefil | administration (sudo avec mot de passe, groupe docker) | SSH par clé uniquement |
| root | — | console VNC uniquement |
| ubuntu | défaut de l'image | verrouillé, nologin |

## Ports exposés sur Internet
| Port | Service | Règle UFW |
|---|---|---|
| 22/tcp (v4 + v6) | sshd | limit |

## Ports locaux (127.0.0.1)
| Port | Service |
|---|---|
| 8090 | demo-web (nginx-unprivileged) |

## Services système
| Service | Rôle | Config versionnée |
|---|---|---|
| ssh | accès distant | ssh/00-hardening.conf |
| ufw | firewall | (règles : voir runbook) |
| fail2ban | bannissement brute-force | fail2ban/sshd.local |
| unattended-upgrades | correctifs de sécurité, reboot auto 04:30 | apt/ |
| chrony | NTP | défaut |
| docker | moteur de conteneurs (dépôt officiel, Compose v2) | docker/daemon.json |

## Stacks Docker
| Stack | Services | Image | Volumes | Exposition |
|---|---|---|---|---|
| demo | web | nginxinc/nginx-unprivileged:stable-alpine | aucun | 127.0.0.1:8090 |

## Arborescence serveur
| Chemin | Rôle |
|---|---|
| /srv/infra | clone lecture seule de kouskefil/contabo-infra |
| /srv/stacks | lien → /srv/infra/stacks |
| /srv/stacks/*/.env | secrets, hors Git, chmod 600 |

## Tâches planifiées
| Timer | Rôle |
|---|---|
| apt-daily.timer | rafraîchit la liste des paquets |
| apt-daily-upgrade.timer | applique les correctifs de sécurité |

## DNS (OVH)
| Enregistrement | Cible | État |
|---|---|---|
| app, gitlab, jenkins, registry (A) | 75.119.129.90 | orphelins, à nettoyer en Phase 3 |
