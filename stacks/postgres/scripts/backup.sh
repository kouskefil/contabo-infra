#!/usr/bin/env bash
# Sauvegarde logique de PostgreSQL — Phase 4.4
# Lancé chaque nuit par pg-backup.timer (systemd), en tant que kouskefil.
# Produit dans /srv/backups/postgres/<AAAA-MM-JJ_HHMM>/ :
#   globals.sql  rôles et mots de passe hachés (pg_dumpall --globals-only)
#   <base>.dump  une sauvegarde par base applicative (pg_dump, format custom)
#   SHA256SUMS   empreintes pour vérifier l'intégrité des fichiers
set -euo pipefail

STACK_DIR=/srv/stacks/postgres
BACKUP_ROOT=/srv/backups/postgres
KEEP=7                                   # nombre de sauvegardes conservées sur le VPS

STAMP="$(date +%F_%H%M)"
DEST="${BACKUP_ROOT}/${STAMP}"
WORK="${DEST}.partial"                   # renommé seulement si tout a réussi

umask 077
mkdir -p "$WORK"
cd "$STACK_DIR"
pg() { docker compose exec -T postgres "$@"; }

# 1. Rôles (nécessaires pour restaurer les droits des bases)
pg pg_dumpall -U postgres --globals-only > "${WORK}/globals.sql"

# 2. Chaque base applicative (hors bases système)
mapfile -t DBS < <(pg psql -U postgres -tAc \
  "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY 1")

for db in "${DBS[@]}"; do
  pg pg_dump -U postgres --format=custom --compress=6 "$db" > "${WORK}/${db}.dump"
  # Contrôle : l'archive doit être lisible par pg_restore
  pg pg_restore --list < "${WORK}/${db}.dump" > /dev/null
done

# 3. Empreintes, puis publication atomique du dossier
(cd "$WORK" && sha256sum -- * > SHA256SUMS)
mv "$WORK" "$DEST"

# 4. Rétention : garder les $KEEP sauvegardes complètes les plus récentes
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*_*' ! -name '*.partial' \
  | sort | head -n -"$KEEP" | xargs -r rm -rf --
# Restes d'une exécution interrompue (plus d'un jour)
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '*.partial' -mmin +1440 -exec rm -rf -- {} +

echo "OK ${STAMP} : ${#DBS[@]} base(s) [${DBS[*]}], $(du -sh "$DEST" | cut -f1)"
