#!/usr/bin/env bash
set -euo pipefail

# ── migrate-db.sh ──────────────────────────────────────────────────────────────
# Spins up a Fargate migrator task and runs drizzle-kit migrate against the
# database via ECS Exec / SSM. No inbound ports or SSH keys required.
#
# The migrator task uses the node-tf-db-migrator image and runs `pnpm db:migrate`
# by default. DATABASE_URL is injected via container overrides so credentials
# never need to be baked into the image.
#
# All variables except DATABASE_URL fall back to terraform outputs if not set.
#
# Required:
#   DATABASE_URL  — postgresql://user:password@host/database (migrator credentials)
#
# Optional (read from terraform outputs if not set):
#   AWS_REGION         default: us-east-1
#   ECS_CLUSTER        terraform/bastion output: cluster_name
#   TASK_DEFINITION    terraform/bastion output: migrator_task_definition
#   SUBNET_ID          first private subnet from terraform/shared output: private_subnet_ids
#   SECURITY_GROUP_ID  terraform/bastion output: security_group_id
#
# Usage:
#   DATABASE_URL="postgresql://migrator:pass@host/db" ./scripts/admin/migrate-db.sh
#
# Tip: prefix the command with a space to omit it from shell history (requires
#   HISTCONTROL=ignorespace or HISTCONTROL=ignoreboth in your shell config):
#    DATABASE_URL="postgresql://migrator:pass@host/db" ./scripts/admin/migrate-db.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$SCRIPT_DIR/../../terraform"

# ── Read terraform outputs as fallbacks ───────────────────────────────────────

AWS_REGION="${AWS_REGION:-us-east-1}"

ECS_CLUSTER="${ECS_CLUSTER:-$(terraform -chdir="$TERRAFORM_ROOT/bastion" output -raw cluster_name 2>/dev/null || true)}"
TASK_DEFINITION="${TASK_DEFINITION:-$(terraform -chdir="$TERRAFORM_ROOT/bastion" output -raw migrator_task_definition 2>/dev/null || true)}"
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-$(terraform -chdir="$TERRAFORM_ROOT/bastion" output -raw security_group_id 2>/dev/null || true)}"
SUBNET_ID="${SUBNET_ID:-$(terraform -chdir="$TERRAFORM_ROOT/shared" output -json private_subnet_ids 2>/dev/null | jq -r '.[0]' || true)}"

# ── Validate required vars ────────────────────────────────────────────────────

missing=()
for var in DATABASE_URL AWS_REGION ECS_CLUSTER TASK_DEFINITION SUBNET_ID SECURITY_GROUP_ID; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: missing required variables (set as env vars or apply terraform/bastion first):" >&2
  for var in "${missing[@]}"; do
    echo "  $var" >&2
  done
  exit 1
fi

# ── Validate DATABASE_URL format ──────────────────────────────────────────────

if [[ ! "$DATABASE_URL" =~ ^postgresql://[^:]+:[^@]+@[^/]+/.+ ]]; then
  echo "Error: DATABASE_URL must be in the format postgresql://user:password@host/database" >&2
  exit 1
fi

# ── Append sslmode=require if not already present ────────────────────────────

if [[ "$DATABASE_URL" != *"sslmode="* ]]; then
  [[ "$DATABASE_URL" == *"?"* ]] && DATABASE_URL="${DATABASE_URL}&sslmode=require" \
                                 || DATABASE_URL="${DATABASE_URL}?sslmode=require"
fi

# ── Spin up migrator task with DATABASE_URL override ─────────────────────────

echo "Starting migrator task..."

TASK_ARN=$(aws ecs run-task \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --task-definition "$TASK_DEFINITION" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SECURITY_GROUP_ID],assignPublicIp=DISABLED}" \
  --overrides "{
    \"containerOverrides\": [{
      \"name\": \"migrator\",
      \"environment\": [{
        \"name\": \"DATABASE_URL\",
        \"value\": \"${DATABASE_URL}\"
      }]
    }]
  }" \
  --query 'tasks[0].taskArn' \
  --output text)

if [[ -z "$TASK_ARN" || "$TASK_ARN" == "None" ]]; then
  echo "Error: failed to start task — check AWS credentials and permissions" >&2
  exit 1
fi

echo "Task ARN: $TASK_ARN"
echo "Waiting for migrations to complete..."

aws ecs wait tasks-stopped \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --tasks "$TASK_ARN"

# ── Check exit code ───────────────────────────────────────────────────────────

EXIT_CODE=$(aws ecs describe-tasks \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' \
  --output text)

if [[ "$EXIT_CODE" == "0" ]]; then
  echo "Migrations completed successfully."
else
  echo "Error: migrations failed with exit code $EXIT_CODE" >&2
  exit 1
fi
