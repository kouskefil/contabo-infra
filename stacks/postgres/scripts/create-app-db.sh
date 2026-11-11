#!/usr/bin/env bash
# Crée un rôle et une base dédiés à une application — Phase 4.3
# Usage : ./scripts/create-app-db.sh <app>      (depuis /srv/stacks/postgres)
# Effets :
#   - rôle <app> (LOGIN, mot de passe aléatoire, aucun autre privilège)
#   - base <app> appartenant à <app>, fermée aux autres rôles
#   - mot de passe écrit dans /srv/stacks/<app>/secrets/db_password (chmod 600), jamais affiché
set -euo pipefail

APP="${1:-}"
if [[ ! "$APP" =~ ^[a-z][a-z0-9_]{1,30}$ ]]; then
  echo "Usage : $0 <app>  (minuscules, chiffres, _ ; 2 à 31 caractères)" >&2
  exit 1
fi

SECRET_DIR="/srv/stacks/${APP}/secrets"
SECRET_FILE="${SECRET_DIR}/db_password"
cd "$(dirname "$0")/.."

if [[ -e "$SECRET_FILE" ]]; then
  echo "Refus : ${SECRET_FILE} existe déjà (l'application semble déjà créée)." >&2
  exit 1
fi

umask 077
mkdir -p "$SECRET_DIR"
PW="$(openssl rand -base64 32 | tr -d '\n/+=' | cut -c1-32)"

# Le SQL passe par l'entrée standard : le mot de passe n'apparaît ni dans `ps` ni dans l'historique
docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -q <<SQL
\set app '${APP}'
\set pw '${PW}'
CREATE ROLE :"app" LOGIN PASSWORD :'pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE DATABASE :"app" OWNER :"app";
REVOKE ALL ON DATABASE :"app" FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE :"app" TO :"app";
SQL

printf '%s' "$PW" > "$SECRET_FILE"
unset PW
echo "OK : rôle et base « ${APP} » créés ; mot de passe dans ${SECRET_FILE}"
