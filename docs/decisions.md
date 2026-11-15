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

## 2026-11-15 — Phase 6 : observabilité auto-hébergée plutôt que Datadog
- Décision : stack auto-hébergée sur le VPS — Prometheus (métriques), Grafana (tableaux de bord), Loki (logs), Grafana Alloy (collecte des logs), Alertmanager (notifications), node-exporter (machine), cAdvisor (conteneurs), blackbox exporter (sondes HTTP).
- Alternative écartée : Datadog (facturation par hôte et par conteneur difficile à prévoir, données d'exploitation hébergées chez un tiers).
- Raison : les ressources sont disponibles (23 Go de RAM, 1,1 Go utilisés avant la phase) ; la compétence est transférable, Prometheus étant le standard de l'écosystème Kubernetes visé en Phase 8 ; aucune donnée ne sort du serveur.
- Contrepartie assumée : une stack de plus à maintenir et à mettre à jour, et qui ne peut rien signaler si le serveur lui-même s'arrête.
- Rétention : métriques 30 jours ou 4 Go ; logs 14 jours.

## 2026-11-15 — Grafana et Prometheus accessibles par tunnel SSH uniquement
- Décision : publiés sur 127.0.0.1 seulement (3000 et 9090). Pas de nom de domaine, pas de passage par Caddy.
- Alternative écartée : exposer grafana.kouskefil.tech derrière Caddy avec authentification.
- Raison : une interface d'administration exposée en permanence sur Internet est une surface d'attaque pour un bénéfice faible, l'usage étant personnel et depuis un seul poste. L'authentification de Grafana devient une deuxième ligne de défense au lieu d'être la seule.
- Réglages associés : accès anonyme désactivé, inscription désactivée, mot de passe admin en secret Compose (GF_SECURITY_ADMIN_PASSWORD__FILE).

## 2026-11-15 — Alertes par Telegram
- Décision : Alertmanager notifie un bot Telegram (« Alerte contabo »), jeton en secret Compose (bot_token_file), `send_resolved: true`.
- Alternatives écartées : e-mail (nécessite un relais SMTP fiable, risque de classement en indésirable, pas de notification immédiate sur le téléphone) ; Discord.
- Réglages : group_by alertname, group_wait 30 s, group_interval 5 min, repeat_interval 12 h.
- Validé de bout en bout le 2026-11-15 : arrêt volontaire de cAdvisor, puis arrêt de la stack demo (message « PROBLÈME » à 22:39, « RÉSOLU » à 22:44).
- Piège rencontré : un bot Telegram ne peut écrire à quelqu'un qu'après que celui-ci a ouvert la conversation et appuyé sur START. Être sur la fiche du bot ne suffit pas — il faut entrer dans la conversation.

## 2026-11-15 — Grafana Alloy à la place de Promtail
- Décision : collecte des logs de conteneurs par Grafana Alloy (discovery.docker → discovery.relabel → loki.source.docker → loki.write).
- Raison : Promtail est en fin de vie depuis le 2 mars 2026 ; Alloy est son successeur désigné.
- Étiquettes conservées : `conteneur`, `stack`, `service` (issues des labels Compose). Loki n'indexe que les étiquettes : en multiplier dégrade les performances, le reste se filtre à la requête.
- Contrepartie assumée : Alloy a accès au socket Docker en lecture — c'est un composant privilégié, comme cAdvisor qui tourne en mode `privileged`. Deux conteneurs ont donc un accès de niveau hôte.

## 2026-11-15 — Trois constats de dépannage à retenir
- **Loki** : l'image ne contient ni `wget` ni `curl`, un healthcheck Docker classique y est donc impossible (conteneur marqué `unhealthy` à tort, et toute la stack bloquée par `depends_on`). Décision : pas de healthcheck sur Loki ; c'est Prometheus qui le surveille, via des jobs dédiés (loki, alloy, grafana, alertmanager, blackbox).
- **Alloy** : avec `cap_drop: [ALL]`, même root est soumis aux contrôles de droits classiques, car `CAP_DAC_OVERRIDE` est retiré. Docker ayant recopié les droits de l'image (`drwxrwx--- alloy alloy`) dans le volume neuf, le conteneur ne pouvait pas y écrire. Décision : `cap_add: [DAC_OVERRIDE]`. Diagnostic obtenu avec `docker run --rm --entrypoint sh <image> -c 'id; ls -ld <chemin>'` — après deux correctifs tentés au jugé, qui n'ont rien donné.
- **Versions d'images** : un tag annoncé par un site de suivi de versions n'existe pas forcément sur le Docker Hub (cas de grafana-oss 13.3.1). Règle adoptée : vérifier avec `docker manifest inspect <image>:<tag>` avant d'épingler, et ne jamais utiliser de tag flottant (`latest`, `v0`, `master`).

## 2026-11-15 — Surveillance des sauvegardes
- Décision : `backup.sh` écrit cinq mesures dans /srv/metrics/pg_backup.prom, lues par node-exporter via le collecteur « textfile ».
- Mécanisme : écriture atomique (fichier temporaire puis `mv`) pour que node-exporter ne lise jamais un fichier à moitié écrit ; `trap 'ecrire_metriques 0' EXIT` enregistre un échec dès le démarrage du script, annulé seulement à la dernière ligne — un script interrompu, tué ou planté laisse donc une trace d'échec.
- Trois règles : échec de la dernière exécution, sauvegarde datant de plus de 36 h, absence de la métrique depuis 2 h.
- La troisième est la plus importante : sans elle, la disparition du fichier rendrait les deux autres muettes, et un silence ressemble à tort à une bonne nouvelle.

## 2026-11-15 — Sondes HTTP (blackbox exporter)
- Décision : blackbox exporter v0.29.1, trois sondes lancées depuis le VPS — demo.kouskefil.tech (2xx attendu), api.kouskefil.tech/ws/clients.wsdl (2xx), api.kouskefil.tech/taches (**401 attendu**).
- Raison : rien ne vérifiait jusque-là ce qu'un visiteur obtient réellement. Un conteneur peut être `healthy` et servir des erreurs ; la surveillance en boîte noire teste le résultat visible.
- La sonde /taches vérifie deux choses à la fois : le service répond, et son authentification est toujours en place. Un passage à 200 serait signalé.
- Trois règles : sonde en échec (5 min), certificat TLS à moins de 21 jours (Caddy renouvelant à 30 jours, un déclenchement signale trois semaines d'échecs de renouvellement), réponse de plus de 5 s pendant 15 min.
- Alternative écartée : une règle « ce conteneur a disparu » — elle exigerait d'inscrire les noms de conteneurs en dur et casserait silencieusement au premier renommage de stack. Les sondes couvrent la disparition comme le blocage ou l'erreur.
- Un job supplémentaire surveille le blackbox exporter lui-même : sans lui, ses trois sondes deviendraient muettes sans un mot.

## 2026-11-15 — Sonde externe : point ouvert
- Besoin : si le VPS s'arrête, Prometheus et Alertmanager s'arrêtent avec lui et aucune alerte ne part. Un outil ne peut pas signaler sa propre mort.
- Tentative : UptimeRobot (offre gratuite, 50 sondes, intervalle de 5 minutes, usage commercial autorisé contrairement à ce qu'indiquaient des comparatifs tiers). Aucune alerte reçue lors du test ; diagnostic non terminé.
- À vérifier à la reprise : sondes actives et non en pause, contact d'alerte vérifié (lien de confirmation cliqué), contact rattaché à chaque sonde. L'API v2 (`getMonitors`, `getAlertContacts`) permet de le contrôler en ligne de commande avec une clé en lecture seule.
- Attention : Telegram ne figure pas dans les canaux de notification de l'offre gratuite d'UptimeRobot — utiliser l'e-mail.
- Leçon méthodologique : un test de panne doit durer **au moins deux fois l'intervalle de contrôle**. « Arrêter une minute » ne prouve rien face à un contrôle toutes les 5 minutes, d'autant qu'UptimeRobot revérifie depuis plusieurs nœuds avant d'ouvrir un incident. Vaut aussi pour les règles Prometheus : une alerte en `for: 15m` ne se déclenchera jamais si la condition ne dure pas un quart d'heure.
