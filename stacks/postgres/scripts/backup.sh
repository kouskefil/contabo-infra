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
METRICS_FILE=/srv/metrics/pg_backup.prom # lu par node-exporter (collecteur textfile)

DEBUT=$(date +%s)

# Écrit le résultat au format Prometheus. L'écriture est atomique (fichier
# temporaire puis renommage) : node-exporter ne lit jamais un fichier à moitié écrit.
ecrire_metriques() {
  local succes="$1" bases="${2:-0}" taille="${3:-0}"
  local tmp
  mkdir -p "$(dirname "$METRICS_FILE")" || return 0
  tmp="$(mktemp "${METRICS_FILE}.XXXXXX")" || return 0
  {
    echo "# HELP pg_backup_last_run_success 1 si la derniere sauvegarde a reussi, 0 sinon"
    echo "# TYPE pg_backup_last_run_success gauge"
    echo "pg_backup_last_run_success ${succes}"
    echo "# HELP pg_backup_last_run_timestamp_seconds Fin de la derniere execution"
    echo "# TYPE pg_backup_last_run_timestamp_seconds gauge"
    echo "pg_backup_last_run_timestamp_seconds $(date +%s)"
    echo "# HELP pg_backup_duration_seconds Duree de la derniere execution"
    echo "# TYPE pg_backup_duration_seconds gauge"
    echo "pg_backup_duration_seconds $(( $(date +%s) - DEBUT ))"
    echo "# HELP pg_backup_databases Nombre de bases sauvegardees"
    echo "# TYPE pg_backup_databases gauge"
    echo "pg_backup_databases ${bases}"
    echo "# HELP pg_backup_size_bytes Taille de la derniere sauvegarde"
    echo "# TYPE pg_backup_size_bytes gauge"
    echo "pg_backup_size_bytes ${taille}"
  } > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$METRICS_FILE"
}

# Quoi qu'il arrive avant la fin du script, on enregistre un echec.
# La derniere ligne annule ce filet et enregistre le succes.
trap 'ecrire_metriques 0' EXIT

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

trap - EXIT
ecrire_metriques 1 "${#DBS[@]}" "$(du -sb "$DEST" | cut -f1)"

echo "OK ${STAMP} : ${#DBS[@]} base(s) [${DBS[*]}], $(du -sh "$DEST" | cut -f1)"
