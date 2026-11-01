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
├── stacks/<stack>/compose.yaml        → lancé depuis /srv/stacks/<stack>/
│   └── .env.example                   (le .env réel reste sur le serveur, chmod 600)
└── docs/  decisions.md · runbook.md · inventaire.md
```

Les fichiers système (ssh, fail2ban, apt, sysctl, docker) sont copiés à la main vers leur cible : le dépôt en garde la référence.

**Secrets** : jamais dans ce dépôt (`.gitignore` : `.env`, `*.key`, `*.pem`, `secrets/`).

## Conventions des stacks Compose
- `restart: unless-stopped`, `init: true`
- ports toujours `127.0.0.1:<port>:<port>` (jamais `0.0.0.0`, sauf reverse proxy)
- `read_only: true` + `tmpfs`, `cap_drop: [ALL]`, `no-new-privileges`
- limites `cpus` / `memory` / `pids`, `healthcheck`, image versionnée
- un réseau dédié par stack
