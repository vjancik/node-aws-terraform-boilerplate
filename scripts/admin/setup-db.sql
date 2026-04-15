-- ── setup-db.sql ───────────────────────────────────────────────────────────────
-- Run once per database as the RDS master user to create two least-privilege users:
--   migrator — DDL rights, used by migration tooling at deploy time only
--   app      — DML only (SELECT/INSERT/UPDATE/DELETE), used by the runtime app
--
-- Passwords are set interactively via \password to avoid appearing in logs or history.
-- Must be run as the RDS master user (db_username in terraform.tfvars).
--
-- Usage (from inside the connect-db.sh session):
--   \i setup-db.sql
--   \password migrator    ← prompted securely, run after script completes
--   \password app         ← prompted securely, run after script completes

-- ── Create migrator user ───────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'migrator') THEN
    CREATE ROLE migrator LOGIN PASSWORD 'migratorpassword';  -- temporary, immediately override with \password migrator
  END IF;
END
$$;

DO $$
BEGIN
  EXECUTE FORMAT('GRANT CONNECT ON DATABASE %I TO %I', CURRENT_DATABASE(), 'migrator');
  EXECUTE FORMAT('GRANT CREATE ON DATABASE %I TO %I', CURRENT_DATABASE(), 'migrator');
END $$;

GRANT USAGE, CREATE ON SCHEMA public TO migrator;

-- Migrator owns all current and future tables/sequences
GRANT ALL ON ALL TABLES IN SCHEMA public TO migrator;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO migrator;

-- ── Create app (runtime) user ──────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app') THEN
    CREATE ROLE app LOGIN PASSWORD 'apppassword';  -- temporary, immediately override with \password app
  END IF;
END
$$;

DO $$
BEGIN
  EXECUTE FORMAT('GRANT CONNECT ON DATABASE %I TO %I', CURRENT_DATABASE(), 'app');
END $$;

GRANT USAGE ON SCHEMA public TO app;

-- App can read and write data but cannot modify schema
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app;

-- ALTER DEFAULT PRIVILEGES FOR ROLE x requires the current user to be a member of x.
-- Grant master user membership in migrator so the default privilege applies correctly.
GRANT migrator TO adminuser;

-- Ensure app gets the same permissions on all future tables created by migrator
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app;

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app;

-- Explicitly deny DDL — app cannot create, alter, or drop schema objects
REVOKE CREATE ON SCHEMA public FROM app;

-- ── Sanity check ──────────────────────────────────────────────────────────────
SELECT rolname, rolcanlogin, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname IN ('migrator', 'app');
