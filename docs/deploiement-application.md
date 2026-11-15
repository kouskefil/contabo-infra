# Déployer une application sur le VPS

Procédure complète, éprouvée sur deux applications : `clients-ws` (Spring Boot, SOAP) et `taches-api` (FastAPI).
Dernière validation : 2026-11-15, test de reboot compris.

> Valable tant que le build se fait sur le VPS. La Phase 7 (GitLab CI) remplacera les étapes 6 et 10.

---

## 1. Vue d'ensemble

### Le trajet d'une requête

```
Internet ──▶ pare-feu UFW ──▶ Caddy ──▶ application ──▶ PostgreSQL
             (ports 80/443)   (HTTPS,    (réseau        (réseau db,
                              routage)   proxy)         jamais exposé)
```

- **Caddy** est le seul conteneur joignable depuis Internet. Il gère les certificats et aiguille chaque chemin vers une application.
- **L'application** ne publie aucun port sur Internet. Caddy la joint par son nom sur le réseau Docker `proxy`.
- **PostgreSQL** n'est joignable que par les applications du réseau `db`.

### Deux dépôts par application

| Dépôt | Contient | Répond à | Sur le VPS |
|---|---|---|---|
| `<app>` (ex. `taches-api`) | code, `Dockerfile` | **quoi** exécuter | `/srv/apps/<app>` |
| `contabo-infra` | `stacks/<stack>/compose.yaml`, `Caddyfile` | **comment** l'exécuter ici | `/srv/infra` (et `/srv/stacks` → `/srv/infra/stacks`) |

Git est la source de vérité : on modifie sur le Mac, on pousse, le serveur récupère. On ne modifie jamais un fichier versionné directement sur le serveur.

### Ce qui n'est jamais dans Git

| Fichier (sur le VPS uniquement) | Rôle |
|---|---|
| `/srv/stacks/<stack>/secrets/db_password` | mot de passe de la base de l'application |
| `/srv/stacks/<stack>/secrets/<autre>` | clé d'API, mot de passe WS-Security… |
| `/srv/stacks/<stack>/.env` | `APP_UID` / `APP_GID` |

Tous en `chmod 600`. Le `.gitignore` du dépôt d'infra exclut `.env` et `secrets/`.

### Conventions de nommage

Pour une application `taches-api` :

| Élément | Convention | Exemple |
|---|---|---|
| Dépôt du code | libre | `taches-api` |
| Stack, base, rôle PostgreSQL | un mot, minuscules, sans tiret | `taches` |
| Alias sur le réseau `proxy` | `<stack>-app` | `taches-app` |
| Image | `<depot>:local` | `taches-api:local` |
| Deploy key | `~/.ssh/github_<depot_avec_underscores>_deploy` | `github_taches_api_deploy` |
| Alias SSH | `github-<depot>` | `github-taches-api` |
| Port local de test | le suivant libre | voir ci-dessous |

Ports locaux (127.0.0.1) déjà attribués : 5432 PostgreSQL, 8085 `clients`, 8086 `taches`. Prochain libre : **8087**.

---

## 2. La procédure, pas à pas

Chaque étape indique **où** l'exécuter. Remplacer `<depot>`, `<stack>` et `<port>`.

### Étape 1 — Préparer le code (Mac)

Le dépôt de l'application doit contenir un `Dockerfile` (modèles en section 4) et respecter ces règles :

- lire ses secrets dans des **fichiers** sous `/run/secrets/`, pas dans des variables d'environnement ;
- lire l'adresse de la base dans `DB_HOST`, `DB_NAME`, `DB_USER` ;
- exposer un point de **santé** qui vérifie aussi la base ;
- s'arrêter proprement sur `SIGTERM` (commande de démarrage en forme « exec ») ;
- ne rien écrire ailleurs que dans `/tmp` ;
- exiger une **authentification** sur tout ce qui sera exposé.

Créer un dépôt **privé et vide** sur GitHub, puis :

```bash
cd /Users/kefilkoussonda/projects/<depot>
git init -b main && git add . && git commit -m "Version initiale"
git remote add origin git@github.com:kouskefil/<depot>.git && git push -u origin main
```

### Étape 2 — Décrire le déploiement (Mac)

Créer `stacks/<stack>/compose.yaml` dans `contabo-infra` à partir du modèle (section 4), puis :

```bash
cd /Users/kefilkoussonda/projects/INFRA
git add stacks/<stack> && git commit -m "Stack <stack>" && git push
```

### Étape 3 — Donner au serveur l'accès au code (VPS)

Une clé par dépôt, en lecture seule.

```bash
ssh-keygen -t ed25519 -N "" -C "contabo-vps:<depot>-readonly" -f ~/.ssh/github_<depot_>_deploy
cat >> ~/.ssh/config <<'EOF'
Host github-<depot>
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_<depot_>_deploy
  IdentitiesOnly yes
EOF
cat ~/.ssh/github_<depot_>_deploy.pub
```

Sur GitHub : dépôt → **Settings → Deploy keys → Add deploy key**, sans « Allow write access ».

```bash
ssh -T github-<depot>
git clone git@github-<depot>:kouskefil/<depot>.git /srv/apps/<depot>
git -C /srv/apps/<depot> config pull.ff only
git -C /srv/infra pull
```

Contrôle : `ls /srv/apps/<depot>` montre le `Dockerfile`, `ls /srv/stacks/<stack>` montre `compose.yaml`.

### Étape 4 — Créer la base (VPS)

```bash
cd /srv/stacks/postgres && ./scripts/create-app-db.sh <stack>
```

Crée un rôle et une base `<stack>` isolés, et écrit le mot de passe dans `/srv/stacks/<stack>/secrets/db_password` sans l'afficher. La base est incluse automatiquement dans la sauvegarde nocturne.

### Étape 5 — Créer les autres secrets et le `.env` (VPS)

```bash
cd /srv/stacks/<stack>
(umask 077 && printf '%s' "$(openssl rand -base64 60 | tr -d '/+=\n' | cut -c1-40)" > secrets/api_key)
printf 'APP_UID=%s\nAPP_GID=%s\n' "$(id -u)" "$(id -g)" > .env && chmod 600 .env
```

Contrôle :

```bash
ls -l secrets/                                             # tout en -rw-------
git -C /srv/infra status --short --ignored | grep <stack>  # uniquement des lignes "!!"
docker compose config --quiet && echo COMPOSE_OK
```

Ranger ensuite chaque secret dans le gestionnaire de mots de passe (`cat secrets/<nom>; echo`, puis `clear`).

### Étape 6 — Construire et démarrer (VPS)

```bash
cd /srv/stacks/<stack>
docker compose build
docker compose up -d && sleep 30
docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
docker compose logs app | tail -10
```

Attendu : `(healthy)` et le port sur `127.0.0.1` uniquement.

### Étape 7 — Tester en local (VPS)

Avant toute exposition, vérifier sur `http://127.0.0.1:<port>` :

- les appels normaux réussissent ;
- un appel **sans authentification est refusé** ;
- une requête invalide est refusée.

### Étape 8 — DNS (OVH), seulement pour un nouveau nom

Si l'application va sous `api.kouskefil.tech/<chemin>`, rien à faire. Pour un nouveau sous-domaine : enregistrement **A** `<nom>` → `75.119.129.90`, puis `dig +short @dns200.anycast.me <nom>.kouskefil.tech A`.

### Étape 9 — Exposer via Caddy (Mac, puis VPS)

**Mac** : ajouter la règle dans `stacks/proxy/Caddyfile` (modèle en section 4), commit, push.

**VPS** : valider **avant** d'appliquer. Un Caddyfile invalide empêcherait Caddy de redémarrer et couperait tous les sites.

```bash
git -C /srv/infra pull
docker run --rm -v /srv/stacks/proxy/Caddyfile:/etc/caddy/Caddyfile:ro caddy:2.11.7-alpine \
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1 | tail -2
```

Si `Valid configuration` :

```bash
cd /srv/stacks/proxy && docker compose restart caddy && sleep 10
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
```

> Un simple `caddy reload` ne suffit pas : le Caddyfile est monté comme fichier unique, et `git pull` le remplace. Le conteneur ne voit le nouveau fichier qu'après un redémarrage.

### Étape 10 — Vérifier depuis l'extérieur (Mac)

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://api.kouskefil.tech/<chemin>        # 401 sans authentification
curl -s -o /dev/null -w '%{http_code}\n' https://api.kouskefil.tech/<sante>         # 404 : non exposé
curl -s -o /dev/null -w '%{http_code}\n' https://api.kouskefil.tech/ws/clients.wsdl # 200 : les autres services répondent toujours
```

### Étape 11 — Documenter

Mettre à jour `docs/inventaire.md` (stack, port, base, secrets, domaine), `docs/runbook.md` (comment tester et mettre à jour) et `docs/decisions.md` (choix notables).

---

## 3. Liste de contrôle avant exposition publique

- [ ] Authentification exigée sur tous les chemins exposés ; un appel sans identifiants est refusé.
- [ ] Seuls les chemins utiles sont routés par Caddy ; santé, documentation et administration répondent 404.
- [ ] Aucun `0.0.0.0` dans `ports:` ; le port de test est sur `127.0.0.1`.
- [ ] Conteneur non root, `read_only`, `cap_drop: [ALL]`, `no-new-privileges`.
- [ ] Limites de mémoire, de CPU et de processus définies.
- [ ] `healthcheck` qui vérifie aussi la base ; état `(healthy)`.
- [ ] `restart: unless-stopped`.
- [ ] Secrets en fichiers `600`, ignorés par Git, copiés dans le gestionnaire de mots de passe.
- [ ] Base créée par `create-app-db.sh` (jamais le rôle `postgres`).
- [ ] Taille des requêtes limitée dans Caddy (`request_body max_size`).
- [ ] Versions des images et des dépendances figées.
- [ ] Caddyfile validé avant redémarrage.

---

## 4. Modèles

### `stacks/<stack>/compose.yaml`

```yaml
name: <stack>

services:
  app:
    build:
      context: /srv/apps/<depot>
    image: <depot>:local
    restart: unless-stopped
    init: true
    user: "${APP_UID:?définir APP_UID dans .env}:${APP_GID:?définir APP_GID dans .env}"
    ports:
      - "127.0.0.1:<port>:<port_interne>"     # tests locaux uniquement
    environment:
      DB_HOST: postgres
      DB_NAME: <stack>
      DB_USER: <stack>
      TZ: Europe/Paris
    secrets:
      - db_password
      - api_key
    read_only: true
    tmpfs:
      - /tmp
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 256M        # JVM : 768M
          pids: 100           # JVM : 300
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:<port_interne>/healthz/ready', timeout=3)"]
      interval: 15s
      timeout: 5s
      retries: 4
      start_period: 40s       # JVM : 90s
    stop_grace_period: 30s
    networks:
      db:
      proxy:
        aliases: [<stack>-app]

secrets:
  db_password:
    file: ./secrets/db_password
  api_key:
    file: ./secrets/api_key

networks:
  db:
    external: true
  proxy:
    external: true
```

Pour une image Java sans `curl` ni Python, le contrôle de santé s'écrit avec bash :

```yaml
      test:
        - CMD
        - bash
        - -c
        - "exec 3<>/dev/tcp/127.0.0.1/8081 && printf 'GET /actuator/health/readiness HTTP/1.0\\r\\n\\r\\n' >&3 && grep -q '\"status\":\"UP\"' <&3"
```

### `Dockerfile` — FastAPI

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.13-slim AS build
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt

FROM python:3.13-slim
ENV PATH=/opt/venv/bin:$PATH PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
COPY --from=build /opt/venv /opt/venv
WORKDIR /srv
COPY app ./app
USER 10001:10001
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*", "--timeout-graceful-shutdown", "20"]
```

### `Dockerfile` — Spring Boot (Maven)

```dockerfile
# syntax=docker/dockerfile:1
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -ntp -DskipTests package \
 && java -Djarmode=tools -jar target/app.jar extract --layers --destination /extracted

FROM eclipse-temurin:21-jre
WORKDIR /application
COPY --from=build /extracted/dependencies/ ./
COPY --from=build /extracted/spring-boot-loader/ ./
COPY --from=build /extracted/snapshot-dependencies/ ./
COPY --from=build /extracted/application/ ./
USER 10001:10001
EXPOSE 8080 8081
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Avec `<finalName>app</finalName>` dans le `pom.xml`. Côté Spring : secrets par `spring.config.import: "optional:configtree:/run/secrets/"`, Actuator sur un port séparé (`management.server.port: 8081`), `server.shutdown: graceful`. Dans la stack : `JAVA_TOOL_OPTIONS: "-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"`.

### Règle Caddy

Sous `api.kouskefil.tech`, à ajouter **avant** le dernier `handle` :

```caddyfile
	@<stack> path /<chemin> /<chemin>/*
	handle @<stack> {
		request_body {
			max_size 1MB
		}
		reverse_proxy <stack>-app:<port_interne>
	}
```

Pour un sous-domaine dédié :

```caddyfile
<nom>.kouskefil.tech {
	import security_headers
	encode zstd gzip
	reverse_proxy <stack>-app:<port_interne>
}
```

---

## 5. Mettre à jour une application

**Mac** : modifier, commit, push.

**VPS** :

```bash
docker tag <depot>:local <depot>:precedent        # garder la version actuelle pour un retour arrière
git -C /srv/apps/<depot> pull
cd /srv/stacks/<stack> && docker compose build && docker compose up -d && sleep 30
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
```

Si seul le `compose.yaml` a changé : `git -C /srv/infra pull`, puis `docker compose up -d`.
Si un secret a changé : `docker compose up -d --force-recreate`.

## 6. Revenir en arrière

**Rapide** (remet l'image précédente, sans reconstruire) :

```bash
docker tag <depot>:precedent <depot>:local
cd /srv/stacks/<stack> && docker compose up -d --force-recreate
```

**Durable** : sur le Mac, `git revert <commit>` puis `git push`, et refaire la mise à jour. Git reste ainsi fidèle à ce qui tourne.

⚠️ Une migration de schéma n'est pas annulée par un retour arrière du code. Avant une mise à jour qui modifie la base : `/srv/infra/stacks/postgres/scripts/backup.sh`.

## 7. Retirer une application

```bash
cd /srv/stacks/<stack> && docker compose down
```

Puis : retirer sa règle du Caddyfile et redémarrer Caddy, supprimer `stacks/<stack>` du dépôt d'infra, et, après une dernière sauvegarde, supprimer la base (`DROP DATABASE <stack>; DROP ROLE <stack>;`), le clone `/srv/apps/<depot>`, la deploy key sur GitHub et l'enregistrement DNS éventuel.

---

## 8. Après un redémarrage du serveur

Rien à faire. Test du 2026-11-15 : les cinq conteneurs étaient `(healthy)` 41 secondes après le reboot, sans aucune relance, et les deux services répondaient par leur adresse publique.

Ce qui le garantit : `restart: unless-stopped` sur chaque service, Docker activé au démarrage, et des applications qui échouent proprement si la base n'est pas prête (Docker les relance alors).

Contrôle rapide :

```bash
uptime && docker ps --format 'table {{.Names}}\t{{.Status}}'
```

---

## 9. Pièges rencontrés

| Symptôme | Cause | Correctif |
|---|---|---|
| Commande refusée ou chemin `/Users/...` | commande du VPS lancée sur le Mac | vérifier avec `whoami; hostname` |
| Dossier `<archive>/` à la racine du dépôt | archive décompressée par double-clic | toujours `unzip -o` depuis la racine du dépôt |
| `Permission denied (publickey)` au clonage | URL en `github.com` au lieu de l'alias, ou clé ajoutée au mauvais dépôt | utiliser `git@github-<depot>:...` |
| `Permission denied` sur `/run/secrets/...` | conteneur lancé sous un autre UID que le propriétaire du fichier | `.env` avec `id -u` / `id -g` |
| `502 Bad Gateway` | application absente du réseau `proxy` | `docker network inspect proxy --format '{{range .Containers}}{{.Name}} {{end}}'` |
| Caddy ignore une modification | fichier remplacé par `git pull`, conteneur non redémarré | `docker compose restart caddy` |
| Tous les sites coupés après une modification de Caddy | Caddyfile invalide | valider avant de redémarrer (étape 9) |
| `network ... could not be found` | réseau externe absent | `docker network create proxy` / `db` |
| Conteneur injoignable au montage d'un dossier | dossier monté sur `/lib` (dossier système) | monter ailleurs, par exemple `/deps` |
| `(unhealthy)` alors que l'application répond | commande de santé inadaptée à l'image | `docker inspect <conteneur> --format '{{json .State.Health}}' \| jq '.Log[-1]'` |
| Port joignable depuis Internet malgré UFW | port publié sur `0.0.0.0` (Docker contourne UFW) | toujours `127.0.0.1:` dans `ports:` |
