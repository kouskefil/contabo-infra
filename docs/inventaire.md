# Inventaire — mis à jour le 2026-11-15 (fin de Phase 5)

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
| 80/tcp (v4) | Caddy (ACME + redirection HTTPS) | allow |
| 443/tcp + 443/udp (v4) | Caddy (HTTPS, HTTP/3) | allow |

## Ports locaux (127.0.0.1)
| Port | Service |
|---|---|
| 5432 | PostgreSQL (administration via tunnel SSH) |
| 8085 | clients-ws (SOAP, accès local pour les tests ; WS-Security requis) |
| 8086 | taches-api (FastAPI, accès local pour les tests ; clé d'API requise) |

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
| proxy | caddy | caddy:2.11.7-alpine | caddy_data (certificats), caddy_config | 0.0.0.0:80, 443/tcp, 443/udp |
| demo | web | nginxinc/nginx-unprivileged:stable-alpine | aucun | via Caddy (alias demo-web sur le réseau proxy) |
| postgres | postgres | postgres:18.6-trixie | postgres_data | 127.0.0.1:5432 ; réseau db (alias postgres) |
| clients | app | clients-ws:local (construite sur le VPS ; Spring Boot 4.1.1, Java 21) | aucun | via Caddy (alias clients-app sur le réseau proxy) ; 127.0.0.1:8085 ; réseau db ; limite 768 Mo / 1 CPU |
| taches | app | taches-api:local (construite sur le VPS ; Python 3.13, FastAPI 0.162.2) | aucun | via Caddy (alias taches-app sur le réseau proxy) ; 127.0.0.1:8086 ; réseau db ; limite 256 Mo / 0,5 CPU |

## Réseaux Docker
| Réseau | Rôle |
|---|---|
| proxy (external) | Caddy ↔ applications exposées |
| db (external) | applications ↔ PostgreSQL |
| <stack>_internal | réseau privé de chaque stack |

## Domaines exposés
| Domaine | Service | Certificat | Contrôles |
|---|---|---|---|
| demo.kouskefil.tech | demo-web:8080 | Let's Encrypt (YE2), renouvellement auto par Caddy | SSL Labs A+, Security Headers A |
| api.kouskefil.tech | clients-app:8080, chemin /ws uniquement (reste : 404) | Let's Encrypt, renouvellement auto par Caddy | WS-Security UsernameToken + anti-rejeu ; Actuator non exposé (404) |
| api.kouskefil.tech/taches | taches-app:8000, chemin /taches uniquement | même certificat | clé d'API (X-API-Key) ; /docs et /healthz non exposés (404) |

## Arborescence serveur
| Chemin | Rôle |
|---|---|
| /srv/infra | clone lecture seule de kouskefil/contabo-infra |
| /srv/stacks | lien → /srv/infra/stacks |
| /srv/apps/clients-ws | clone lecture seule de kouskefil/clients-ws (source du build) |
| /srv/apps/taches-api | clone lecture seule de kouskefil/taches-api (source du build) |
| /srv/stacks/*/.env, /srv/stacks/*/secrets/ | secrets, hors Git, chmod 600 |
| /srv/backups/postgres | sauvegardes PostgreSQL (7 conservées), chmod 700 |

## Tâches planifiées
| Timer | Rôle |
|---|---|
| apt-daily.timer | rafraîchit la liste des paquets |
| apt-daily-upgrade.timer | applique les correctifs de sécurité |
| pg-backup.timer | 02:30 : sauvegarde PostgreSQL (systemd/pg-backup.*) |

## DNS (OVH)
| Enregistrement | Cible | État |
|---|---|---|
| @ (A), www (A) | 75.119.129.90 | non servis pour l'instant |
| demo (A) | 75.119.129.90 | servi par Caddy |
| api (A) | 75.119.129.90 | servi par Caddy (clients-ws sur /ws, taches-api sur /taches) |
| @ CAA | 0 issue "letsencrypt.org" | actif |
| @ MX, SPF, DKIM (ovhmo-selector-1/2) | messagerie OVH | ne pas modifier |

## Secrets applicatifs (hors Git)
| Fichier | Rôle |
|---|---|
| /srv/stacks/postgres/secrets/postgres_password | superutilisateur PostgreSQL |
| /srv/stacks/<app>/secrets/db_password | mot de passe du rôle de l'application |
| /srv/stacks/clients/secrets/ws_password | WS-Security, compte `partenaire` |
| /srv/stacks/taches/secrets/api_key | clé d'API de taches-api |

## Bases PostgreSQL
| Base | Propriétaire | Secret | Sauvegarde |
|---|---|---|---|
| demo | demo | /srv/stacks/demo/secrets/db_password | nocturne, restauration testée le 2026-11-11 |
| clients | clients | /srv/stacks/clients/secrets/db_password | nocturne (détection automatique) |
| taches | taches | /srv/stacks/taches/secrets/db_password | nocturne (détection automatique) |

## Points ouverts
- clients-ws : pas de tests automatisés (à traiter dans le projet de formation SOAP) ; cache anti-rejeu en mémoire (une seule instance).
- Mot de passe WS-Security (secrets/ws_password) à ranger dans le gestionnaire de mots de passe.
- Caddyfile monté comme fichier unique : redémarrage de Caddy nécessaire après chaque modification (montage par dossier à prévoir).
- Secrets à ranger dans le gestionnaire de mots de passe : ws_password (clients), api_key (taches).
- Dépendances Python transitives non verrouillées (taches-api) : à traiter en Phase 7.
- Deploy keys du serveur : github_infra_deploy, github_clients_ws_deploy, github_taches_api_deploy (lecture seule).
- ⚠️ Sauvegardes uniquement sur le VPS : envoi chiffré hors VPS (restic) à mettre en place, destination à choisir.
- Mot de passe superutilisateur PostgreSQL à ranger dans le gestionnaire de mots de passe.
