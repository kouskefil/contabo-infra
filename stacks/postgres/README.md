# Stack postgres

- Image : postgres:18.6-trixie. Mise à jour mineure : changer le tag (commit), `docker pull`, `docker compose up -d` (environ 1 trimestre).
- Mot de passe superutilisateur : `secrets/postgres_password` (serveur uniquement, chmod 600, ignoré par Git) + gestionnaire de mots de passe.
- Réseau : `db` (external), alias `postgres`. Les applications s'y connectent avec `postgres:5432`.
- Accès admin : `docker compose exec postgres psql -U postgres`, ou depuis le Mac via le tunnel SSH `contabo-tunnel` (127.0.0.1:5432).
- Nouvelle application : `./scripts/create-app-db.sh <app>` → rôle + base dédiés, mot de passe dans `/srv/stacks/<app>/secrets/db_password`.
- ⚠️ Jamais `docker compose down -v` : supprime le volume postgres_data, donc toutes les bases.
