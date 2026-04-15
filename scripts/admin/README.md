# Admin Scripts

## connect-db.sh

Spins up a Fargate bastion task and opens an interactive psql session via ECS Exec / SSM. No SSH keys or open ports required — IAM is the only access control layer.

On connect, `setup-db.sql` is automatically downloaded from S3 into the working directory.

### Prerequisites

The script uses ECS Exec which requires the AWS Session Manager plugin — a separate binary from the AWS CLI:

```bash
# Ubuntu/Debian
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/session-manager-plugin.deb
sudo dpkg -i /tmp/session-manager-plugin.deb

# macOS
brew install --cask session-manager-plugin

# Verify
session-manager-plugin --version
```

### Usage

```bash
 DATABASE_URL="postgresql://user:pass@host/db" ./scripts/admin/connect-db.sh
```

Prefix with a space to omit credentials from shell history (requires `HISTCONTROL=ignorespace` or `ignoreboth`, which is the common default).

### Transferring additional files into the session

ECS Exec is a pure TTY — no SSH daemon means no `scp` or `rsync`. Use S3 presigned URLs instead:

**1. Upload the file to S3**
```bash
aws s3 cp my-migration.sql s3://$(terraform -chdir=terraform/bastion output -raw admin_bucket)/my-migration.sql
```

**2. Inside the shell session, download it**
```sh
aws s3 cp s3://your-bucket/my-migration.sql .
psql "$DATABASE_URL" -f my-migration.sql
```

---

## setup-db.sql

Run once per database as the RDS master user to provision two least-privilege users:

| User | Permissions | Used by |
|------|------------|---------|
| `migrator` | Full DDL — create/drop schemas, tables, indexes, functions | Migration tooling at deploy time |
| `app` | DML only — SELECT, INSERT, UPDATE, DELETE | Runtime application |

Managed as a versioned S3 object via `terraform/bastion` — apply bastion terraform after editing to sync changes to S3.

### Usage

`setup-db.sql` is automatically downloaded when you connect via `connect-db.sh`. Inside the psql session:

```
\i setup-db.sql
\password migrator
\password app
```

Passwords are set interactively via `\password` so they never appear in logs or shell history.

---

## Common Operations

### Inspect effective Postgres configuration (including RDS-managed values)
```sql
SELECT name, setting, unit FROM pg_settings ORDER BY name;
```

### Check current connections
```sql
SELECT count(*), state FROM pg_stat_activity GROUP BY state;
```

### List databases and sizes
```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;
```

### List tables and sizes
```sql
SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC;
```

---

## Planned Extensions

### EC2 SSH Bastion (Terraform + Ansible)

#### Motivation

The ECS Exec bastion covers migrations and one-off SQL sessions well, but it hits a hard ceiling for developer workflows:

- **No port forwarding** — Drizzle Studio (`drizzle-kit studio`) requires a direct TCP connection to the database. ECS Exec is a pure TTY with no tunneling capability; there is no way to forward a local port to RDS through a Fargate task.
- **No file transfer** — `scp` and `rsync` require an SSH daemon. The S3 presigned URL workaround works but is friction-heavy for frequent use.
- **No `pg_dump` / `pg_restore`** — piping large dumps through ECS Exec is impractical; there is no clean path to pull a prod snapshot to a local dev machine.

A Terraform-managed EC2 bastion with Ansible provisioning would solve all of the above:

- Stop the instance when not in use — cost is effectively just the EBS volume (~$1/mo for 8GB gp3 when stopped)
- SSH port forwarding → `localhost:5432` → RDS, enabling Drizzle Studio against prod/staging
- Direct `pg_dump` to local machine via SSH pipe
- Ansible ensures the instance is reproducibly configured (postgres client, aws cli, tooling) without manual setup steps
- Same security model as ECS bastion — IAM instance profile, private subnet, no inbound ports except SSH from a known CIDR or SSM
