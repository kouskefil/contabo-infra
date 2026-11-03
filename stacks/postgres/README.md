# Stack postgres

- Mot de passe superutilisateur : `secrets/postgres_password` (serveur uniquement, chmod 600, ignoré par Git).
- Réseau : `db` (external), alias `postgres`. Les applications s'y connectent avec `postgres:5432`.
- Accès admin : `docker compose exec postgres psql -U postgres`, ou depuis le Mac via le tunnel SSH `contabo-tunnel` (127.0.0.1:5432).
- ⚠️ Jamais `docker compose down -v` : supprime le volume postgres_data, donc toutes les bases.
