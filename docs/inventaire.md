# Inventaire — mis à jour le 2026-11-15 (fin de Phase 6)

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
| 3000 | Grafana (tunnel SSH) |
| 5432 | PostgreSQL (administration via tunnel SSH) |
| 8085 | clients-ws (SOAP, accès local pour les tests ; WS-Security requis) |
| 8086 | taches-api (FastAPI, accès local pour les tests ; clé d'API requise) |
| 9090 | Prometheus (tunnel SSH) |

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
| monitoring | prometheus, grafana, loki, alloy, alertmanager, node-exporter, cadvisor, blackbox | voir tableau ci-dessous | prometheus_data, grafana_data, loki_data, alloy_data, alertmanager_data | 127.0.0.1:3000 (grafana), 127.0.0.1:9090 (prometheus) ; les six autres ne publient aucun port |

## Stack monitoring — versions et rôles
| Service | Image | Rôle | Particularité |
|---|---|---|---|
| prometheus | prom/prometheus:v3.13.5 | collecte et stockage des métriques, évaluation des règles | rétention 30 j / 4 Go ; `--web.enable-lifecycle` (rechargement à chaud) |
| grafana | grafana/grafana-oss:13.0.2 | tableaux de bord | sources provisionnées (Prometheus, Loki) ; anonyme et inscription désactivés |
| loki | grafana/loki:3.7.8 | stockage des logs | rétention 14 j ; **pas de healthcheck** (image sans wget/curl) |
| alloy | grafana/alloy:v1.20.0 | collecte des logs des conteneurs | socket Docker en lecture ; `cap_add: [DAC_OVERRIDE]` |
| alertmanager | prom/alertmanager:v0.32.0 | regroupement et envoi des alertes | notifications Telegram, jeton en secret |
| node-exporter | prom/node-exporter:v1.12.0 | métriques de la machine | collecteur textfile → /srv/metrics |
| cadvisor | gcr.io/cadvisor/cadvisor:v0.52.1 | métriques par conteneur | **mode privileged** |
| blackbox | prom/blackbox-exporter:v0.29.1 | sondes HTTP depuis le VPS | modules http_200 et http_401 |

## Surveillance — cibles et règles
| Jobs Prometheus (10) | node, cadvisor, prometheus, grafana, loki, alloy, alertmanager, blackbox, sondes-publiques, sondes-protegees |
|---|---|
| Sondes HTTP (3) | demo.kouskefil.tech (2xx), api.kouskefil.tech/ws/clients.wsdl (2xx), api.kouskefil.tech/taches (401 attendu) |

| Groupe de règles | Règles |
|---|---|
| machine (6) | CibleInjoignable, DisqueBientotPlein, DisqueSatureDans24h, MemoireFaible, SwapImportant, ChargeCpuElevee |
| conteneurs (2) | ConteneurEnBoucle, ConteneurProcheDeSaLimite |
| sauvegardes (3) | SauvegardeEnEchec, SauvegardeTropAncienne, MetriqueSauvegardeAbsente |
| sondes (3) | SondeHttpEnEchec, CertificatBientotExpire, ReponseHttpLente |

Notifications : bot Telegram « Alerte contabo », `send_resolved` activé, group_wait 30 s, group_interval 5 min, repeat_interval 12 h. Chaîne validée de bout en bout le 2026-11-15.

## Réseaux Docker
| Réseau | Rôle |
|---|---|
| proxy (external) | Caddy ↔ applications exposées |
| db (external) | applications ↔ PostgreSQL |
| monitoring (interne à la stack, nom complet `monitoring_monitoring`) | services de surveillance entre eux |
| <stack>_internal | réseau privé de chaque stack |

## Domaines exposés
| Domaine | Service | Certificat | Contrôles |
|---|---|---|---|
| demo.kouskefil.tech | demo-web:8080 | Let's Encrypt (YE2), renouvellement auto par Caddy | SSL Labs A+, Security Headers A ; sonde HTTP + alerte d'expiration |
| api.kouskefil.tech | clients-app:8080, chemin /ws uniquement (reste : 404) | Let's Encrypt, renouvellement auto par Caddy | WS-Security UsernameToken + anti-rejeu ; Actuator non exposé (404) ; sonde sur le WSDL |
| api.kouskefil.tech/taches | taches-app:8000, chemin /taches uniquement | même certificat | clé d'API (X-API-Key) ; /docs et /healthz non exposés (404) ; sonde vérifiant le 401 |

## Arborescence serveur
| Chemin | Rôle |
|---|---|
| /srv/infra | clone lecture seule de kouskefil/contabo-infra |
| /srv/stacks | lien → /srv/infra/stacks |
| /srv/apps/clients-ws | clone lecture seule de kouskefil/clients-ws (source du build) |
| /srv/apps/taches-api | clone lecture seule de kouskefil/taches-api (source du build) |
| /srv/stacks/*/.env, /srv/stacks/*/secrets/ | secrets, hors Git, chmod 600 |
| /srv/backups/postgres | sauvegardes PostgreSQL (7 conservées), chmod 700 |
| /srv/metrics | métriques écrites par les scripts, lues par node-exporter (pg_backup.prom) |

## Tâches planifiées
| Timer | Rôle |
|---|---|
| apt-daily.timer | rafraîchit la liste des paquets |
| apt-daily-upgrade.timer | applique les correctifs de sécurité |
| pg-backup.timer | 02:30 : sauvegarde PostgreSQL (systemd/pg-backup.*), métriques dans /srv/metrics |

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
| /srv/stacks/monitoring/secrets/grafana_admin_password | compte admin de Grafana |
| /srv/stacks/monitoring/secrets/telegram_token | jeton du bot Telegram d'alerte |

## Bases PostgreSQL
| Base | Propriétaire | Secret | Sauvegarde |
|---|---|---|---|
| demo | demo | /srv/stacks/demo/secrets/db_password | nocturne, restauration testée le 2026-11-11 |
| clients | clients | /srv/stacks/clients/secrets/db_password | nocturne (détection automatique) |
| taches | taches | /srv/stacks/taches/secrets/db_password | nocturne (détection automatique) |

## Points ouverts
- ⚠️ **Sauvegardes uniquement sur le VPS** : envoi chiffré hors VPS (restic) à mettre en place, destination à choisir (Backblaze B2 recommandé). Doit inclure les secrets (.env, secrets/). C'est le point le plus important.
- ⚠️ **Sonde externe non opérationnelle** : UptimeRobot configuré mais aucune alerte reçue au test ; diagnostic à reprendre (sondes actives, contact vérifié, contact rattaché aux sondes). Tant qu'elle n'est pas en place, un arrêt complet du serveur ne déclenche aucune notification.
- Secrets à ranger dans le gestionnaire de mots de passe : superutilisateur PostgreSQL, ws_password (clients), api_key (taches), mot de passe admin Grafana, jeton du bot Telegram.
- Grafana 13.0 : fin de support annoncée pour début 2027 → montée de version à planifier.
- Deux conteneurs disposent d'un accès de niveau hôte, en connaissance de cause : cAdvisor (`privileged`) et Alloy (socket Docker en lecture).
- Fichiers montés seuls (Caddyfile, prometheus.yml, config.alloy…) : recréation du conteneur nécessaire après chaque `git pull` ; montage par dossier à envisager.
- clients-ws : pas de tests automatisés (à traiter dans le projet de formation SOAP) ; cache anti-rejeu en mémoire (une seule instance).
- Dépendances Python transitives non verrouillées (taches-api) : à traiter en Phase 7.
- Deploy keys du serveur : github_infra_deploy, github_clients_ws_deploy, github_taches_api_deploy (lecture seule).
