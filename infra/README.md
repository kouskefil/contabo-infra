# infra — VPS Contabo (kouskefil.tech)

Fichiers de configuration versionnés du VPS. Chaque fichier indique sa **cible** sur le serveur en en-tête.

```
infra/
├── ssh/00-hardening.conf              → /etc/ssh/sshd_config.d/
├── fail2ban/sshd.local                → /etc/fail2ban/jail.d/
├── apt/20auto-upgrades                → /etc/apt/apt.conf.d/
├── apt/52unattended-upgrades-local    → /etc/apt/apt.conf.d/
├── sysctl/99-swap.conf                → /etc/sysctl.d/
└── fstab/swap.fstab                   → ligne à ajouter à /etc/fstab
```

Phases à venir : `docker/` (Phase 2), `proxy/` (Phase 3), `postgres/` (Phase 4), `apps/` (Phase 5), `observability/` (Phase 6), `k8s/` (Phase 8), `bootstrap/cloud-init.yaml` (reproduction du socle).

**Secrets** : jamais dans ce dépôt. Les fichiers `.env` restent sur le serveur, hors Git (`.gitignore`).
