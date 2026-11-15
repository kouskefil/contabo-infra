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

## 2026-11-01 — Docker Engine depuis le dépôt officiel
- Décision : docker-ce + buildx + compose v2 depuis download.docker.com (suite `resolute`).
- Alternative écartée : paquet `docker.io` d'Ubuntu (souvent en retard).
- Conséquence : Docker non couvert par unattended-upgrades → mise à jour manuelle (`sudo apt upgrade`), sans coupure grâce à live-restore.

## 2026-11-01 — Groupe docker pour kouskefil
- Décision : kouskefil membre du groupe `docker`, en connaissance de cause (équivalent root, contourne le mot de passe sudo).
- Alternatives écartées : `sudo docker` systématique (pénible, incompatible avec le déploiement automatisé) ; Docker rootless (complexité, limites réseau).
- Raison : la barrière principale reste la clé SSH (passphrase, AllowUsers).

## 2026-11-01 — Configuration du démon Docker
- Décision : logs json-file 10 Mo × 3 compressés ; `"ip": "127.0.0.1"` (ports publiés en local par défaut) ; live-restore ; no-new-privileges ; pools d'adresses 172.20.0.0/14 en /24.
- Raison : éviter la saturation du disque par les logs et le contournement d'UFW par les ports publiés (constaté en test : un port publié sur 0.0.0.0 est joignable depuis Internet sans règle UFW).
- Règle : jamais `0.0.0.0` dans un `ports:`, sauf pour le reverse proxy.

## 2026-11-01 — Conventions des stacks Compose
- Décision : une stack par dossier `stacks/<nom>/` ; compose.yaml versionné, `.env` sur le serveur uniquement (chmod 600) avec `.env.example` versionné ; durcissement par défaut (read_only, cap_drop ALL, limites, healthcheck, init, réseau dédié).

## 2026-11-01 — Git comme source de vérité du serveur
- Décision : dépôt `kouskefil/contabo-infra` cloné dans /srv/infra via une deploy key en lecture seule (alias SSH `github-infra`), `pull.ff only` ; `/srv/stacks` est un lien vers `/srv/infra/stacks`.
- Alternatives écartées : copier-coller manuel (dérive, pas d'historique) ; clé SSH personnelle sur le serveur (accès à tout le compte GitHub).
- Structure du dépôt : tout à la racine (pas de sous-dossier infra/). Les archives se décompressent avec `unzip -o` depuis la racine du dépôt.

## 2026-11-03 — Reverse proxy Caddy
- Décision : Caddy (image figée caddy:2.11.7-alpine), configuration dans stacks/proxy/Caddyfile versionné.
- Alternatives écartées : Traefik (labels dispersés, accès au socket Docker = équivalent root sur le composant le plus exposé ; l'ingress Traefik de k3s se configure autrement) ; Nginx (gestion manuelle des certificats).
- Seule stack publiée sur 0.0.0.0 (80/tcp, 443/tcp, 443/udp). Les applications ne publient plus de port : elles rejoignent le réseau Docker externe `proxy` avec un alias unique (ex. demo-web).
- En-têtes communs : HSTS 1 an (sans includeSubDomains), nosniff, X-Frame-Options DENY, Referrer-Policy, Permissions-Policy ; Server et Via retirés. CSP définie par application (Phase 5).
- Validation externe (demo.kouskefil.tech) : SSL Labs A+, securityheaders.com A (seule la CSP manque, volontairement).

## 2026-11-03 — DNS
- Décision : un enregistrement A par service exposé, pas de wildcard ; IPv4 uniquement pour l'instant (AAAA reporté après validation IPv6 du proxy).
- CAA `0 issue "letsencrypt.org"` sur la racine.
- Nettoyage : gitlab, jenkins, registry, ftp, grafana, datadog supprimés ; api conservé. Messagerie OVH (MX, SPF, DKIM) inchangée.
- Racine et www : pointent vers le VPS mais ne sont servis par rien pour l'instant (choix assumé).

## 2026-11-03 — PostgreSQL conteneurisé
- Décision : PostgreSQL 18 dans un conteneur (image postgres:18.6-trixie, Debian), volume nommé postgres_data monté sur /var/lib/postgresql (PGDATA = /var/lib/postgresql/18/docker).
- Alternatives écartées : installation native (hors du modèle Git/Compose, migration k3s plus difficile) ; PostgreSQL 19 (sortie officielle le 19/11/2026, trop récente) ; image Alpine (collations musl, risque d'index incohérents).
- Contrepartie assumée : mises à jour mineures manuelles (changement de tag, environ une fois par trimestre).
- Réglages : shared_buffers 1 Go, effective_cache_size 4 Go, work_mem 16 Mo, maintenance_work_mem 256 Mo, data checksums, scram-sha-256, requêtes > 500 ms journalisées ; limite 4 Go / 2 CPU ; shm_size 256 Mo ; arrêt gracieux 60 s.
- Mot de passe superutilisateur en secret Compose (secrets/postgres_password, chmod 600, hors Git), pas en variable d'environnement.
- Accès : réseau Docker `db` (alias postgres) pour les applications ; 127.0.0.1:5432 pour l'administration via tunnel SSH. Jamais exposé sur Internet.

## 2026-11-11 — Un rôle et une base par application
- Décision : script create-app-db.sh : rôle LOGIN sans autre privilège, base dont il est propriétaire, REVOKE ALL FROM PUBLIC ; mot de passe aléatoire écrit dans /srv/stacks/<app>/secrets/db_password, jamais affiché. Bases postgres et template1 fermées aux rôles applicatifs.
- Règle : aucune application ne se connecte avec le rôle postgres.
- Vérifié : un rôle applicatif ne peut ni se connecter aux autres bases, ni créer de base, ni créer de rôle.

## 2026-11-11 — Sauvegardes PostgreSQL
- Décision : pg_dump (format custom) de chaque base applicative + pg_dumpall --globals-only, chaque nuit à 02:30 (timer systemd, Persistent=true), vérification par pg_restore --list et SHA256SUMS, publication atomique, 7 sauvegardes conservées dans /srv/backups/postgres. RPO accepté : 24 h.
- Alternatives écartées : copie des fichiers à chaud (incohérente) ; archivage WAL avec pgBackRest/WAL-G (RPO de quelques minutes, complexité non justifiée aujourd'hui) ; cron (pas de rattrapage, logs perdus).
- Restauration testée le 2026-11-11 : restauration dans une base séparée et reconstruction complète après suppression de table (pg_restore -C), empreintes MD5 et droits (datacl) identiques.
- ⚠️ Point ouvert : les sauvegardes sont sur le VPS uniquement. Envoi chiffré hors VPS (restic) à mettre en place dès le choix de la destination (Backblaze B2 recommandé). Inclura aussi les secrets (.env, secrets/).

## 2026-11-14 — CI/CD : GitLab CI retenu, Nexus écarté (à mettre en œuvre en Phase 7)
- Décision : GitLab CI préféré à GitHub Actions ; pas de Nexus (le registry de GitLab ou un registry léger suffira).
- Refusé : installer GitLab + Nexus dès la Phase 5 (8 Go minimum pour GitLab, 4 à 8 Go pour Nexus, aucune observabilité en place, GitLab 18 n'accepte pas PostgreSQL 18).
- À trancher en Phase 7 : GitLab auto-hébergé en mode mémoire réduite, ou gitlab.com avec un runner sur le VPS.

## 2026-11-14 — Première application : service SOAP clients-ws
- Décision : première application en SOAP (et non REST), contract-first avec Spring Web Services : le XSD est la source de vérité, classes JAXB générées à la compilation, WSDL généré à l'exécution, validation XSD des requêtes et réponses, exceptions métier traduites en SOAP Fault (@SoapFault).
- Pile : Spring Boot 4.1.1, Java 21, Maven, JPA + Flyway sur la base `clients`. Pas encore de tests automatisés (prévus en 5.3).
- Dépôt séparé `kouskefil/clients-ws` (code) ; la stack Compose reste dans contabo-infra (stacks/clients). Image construite sur le VPS depuis /srv/apps/clients-ws (deploy key en lecture seule, alias `github-clients-ws`), en attendant la CI de la Phase 7.
- Secret de base lu par Spring via configtree (/run/secrets/db_password) ; conteneur exécuté avec l'UID de kouskefil pour pouvoir lire le fichier secret (les secrets Compose de type fichier gardent les droits de l'hôte).
- Actuator sur un port d'administration séparé (8081), jamais exposé.
- Exposition : 127.0.0.1:8085 uniquement tant que le service n'avait pas d'authentification ; exposé publiquement le 2026-11-15 après WS-Security (voir plus bas).

## 2026-11-15 — WS-Security et exposition publique de clients-ws
- Décision : authentification WS-Security UsernameToken (PasswordDigest : nonce + horodatage + mot de passe), validée par Wss4jSecurityInterceptor (Spring-WS 5.0.2, WSS4J 4.0.1). Compte `partenaire`, mot de passe dans /srv/stacks/clients/secrets/ws_password (secret Compose, lu via configtree).
- Ordre des intercepteurs : sécurité avant validation XSD (un appelant non authentifié n'apprend rien sur sa requête). Vérifié.
- Anti-rejeu : MemoryReplayCache (WSS4J) branché par setValidationReplayCache. Constat : sans cache, un même message était accepté deux fois. Limites assumées : cache vidé au redémarrage (couvert par la fenêtre de 5 minutes de l'horodatage) et propre à une instance (SpringReplayCache partagé à prévoir si plusieurs instances).
- Exposition : https://api.kouskefil.tech/ws via Caddy. Seul /ws est transmis (corps limité à 1 Mo) ; Actuator et le reste répondent 404. Le WSDL reste lisible sans authentification (contrat public).
- Alternatives écartées : exposer sans authentification ; authentification HTTP Basic au niveau de Caddy (ne voyage pas avec le message SOAP).

## 2026-11-15 — Périmètre : la formation SOAP sort de ce projet
- Décision : ce projet reste centré sur l'infrastructure. L'apprentissage de SOAP (XSD, WSDL, Faults, WS-Security, tests, client, MTOM, versionnement) se fera dans un projet Claude séparé, à partir d'un dossier de passation construit sur clients-ws.
- Suite de la Phase 5 : application FastAPI, test de reboot, puis document complet du processus de déploiement d'une application.
- Méthode : étapes plus petites, concept expliqué avant la commande.

## 2026-11-15 — Deuxième application : taches-api (FastAPI)
- Décision : API de référence FastAPI (Python 3.13, psycopg 3 avec pool, sans ORM), déployée selon le même modèle que clients-ws : dépôt `kouskefil/taches-api`, stack `stacks/taches`, base `taches`, build sur le VPS.
- Authentification par clé d'API (en-tête X-API-Key, secret `secrets/api_key`, comparaison en temps constant).
- Exposition : https://api.kouskefil.tech/taches via Caddy ; /docs et /healthz non routés (404).
- Versions figées dans requirements.txt (fastapi 0.162.2, uvicorn 0.54.0, psycopg 3.3.5) ; dépendances transitives non verrouillées (à traiter en Phase 7).
- Caddyfile validé par un conteneur jetable avant chaque redémarrage de Caddy.

## 2026-11-15 — Test de reboot réussi
- Constat : après `sudo reboot`, les cinq conteneurs (caddy, postgres, demo, clients, taches) sont `healthy` en 41 secondes, sans aucune relance ; pare-feu, fail2ban, swap et timer de sauvegarde actifs ; les deux services répondent par leur adresse publique.
- Conséquence : le reboot automatique nocturne (04:30) est validé pour les applications en place.

## 2026-11-15 — Procédure de déploiement documentée
- Décision : docs/deploiement-application.md décrit la procédure complète (deux dépôts, deploy key, base, secrets, build, tests, exposition, mise à jour, retour arrière, pièges). À réviser en Phase 7 quand GitLab CI remplacera le build sur le VPS.
- docs/passation-formation-soap.md : dossier de contexte pour le projet séparé de formation SOAP.
