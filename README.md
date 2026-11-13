# contabo-infra — VPS Contabo (kouskefil.tech)

Configuration versionnée du VPS. **Source de vérité** : on modifie ici (Mac), on pousse, puis `git -C /srv/infra pull` sur le serveur. Ne jamais modifier un fichier directement sur le serveur.

Sur le serveur : clone en lecture seule dans `/srv/infra` (deploy key), `/srv/stacks -> /srv/infra/stacks`.

```
.
├── ssh/00-hardening.conf              → /etc/ssh/sshd_config.d/
├── fail2ban/sshd.local                → /etc/fail2ban/jail.d/
├── apt/20auto-upgrades                → /etc/apt/apt.conf.d/
├── apt/52unattended-upgrades-local    → /etc/apt/apt.conf.d/
├── sysctl/99-swap.conf                → /etc/sysctl.d/
├── fstab/swap.fstab                   → ligne ajoutée à /etc/fstab
├── docker/daemon.json                 → /etc/docker/daemon.json
├── systemd/pg-backup.{service,timer}  → /etc/systemd/system/
├── stacks/
│   ├── proxy/      Caddy (seul service exposé sur Internet)
│   ├── postgres/   PostgreSQL 18 + scripts (create-app-db, backup)
│   └── demo/       stack modèle
└── docs/  decisions.md · runbook.md · inventaire.md
```

Les fichiers système sont copiés à la main vers leur cible : le dépôt en garde la référence.

**Archives fournies** : toujours `unzip -o <archive>.zip` depuis la racine du dépôt (jamais de double-clic).

**Secrets** : jamais dans ce dépôt (`.gitignore` : `.env`, `*.key`, `*.pem`, `secrets/`).

## Conventions des stacks Compose
- `restart: unless-stopped`, `init: true`
- aucun `ports:` pour les applications : réseau `proxy` (exposition via Caddy) et/ou `db` (PostgreSQL), avec alias unique
- `0.0.0.0` interdit, sauf pour Caddy
- `read_only: true` + `tmpfs`, `cap_drop: [ALL]`, `no-new-privileges`
- limites `cpus` / `memory` / `pids`, `healthcheck`, image à version figée
- secrets en fichiers (`secrets/`, chmod 600), montés en secrets Compose
