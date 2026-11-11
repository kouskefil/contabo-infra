-- Durcissement initial du cluster — Phase 4.3 (à exécuter une fois, idempotent)
-- Aucun rôle applicatif ne peut se connecter aux bases d'administration
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
REVOKE CONNECT ON DATABASE template1 FROM PUBLIC;
