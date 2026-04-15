#!/usr/bin/env bash
set -euo pipefail

# ── connect-db.sh ──────────────────────────────────────────────────────────────
# Spins up a Fargate bastion task and opens an interactive psql session via
# ECS Exec / SSM. No inbound ports or SSH keys required.
#
# All variables except DATABASE_URL fall back to terraform outputs if not set.
#
# Required:
#   DATABASE_URL  — postgresql://user:password@host/database (credentials, set manually)
#
# Optional (read from terraform outputs if not set):
#   AWS_REGION         default: us-east-1
#   ECS_CLUSTER        terraform/bastion output: cluster_name
#   TASK_DEFINITION    terraform/bastion output: task_definition
#   SUBNET_ID          first private subnet from terraform/shared output: private_subnet_ids
#   SECURITY_GROUP_ID  terraform/bastion output: security_group_id
#
# Usage:
#   DATABASE_URL="postgresql://user:pass@host/db" ./scripts/admin/connect-db.sh
#
# Tip: prefix the command with a space to omit it from shell history (requires
#   HISTCONTROL=ignorespace or HISTCONTROL=ignoreboth in your shell config, which is common default):
#    DATABASE_URL="postgresql://user:pass@host/db" ./scripts/admin/connect-db.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$SCRIPT_DIR/../../terraform"

# ── Read terraform outputs as fallbacks ───────────────────────────────────────

AWS_REGION="${AWS_REGION:-us-east-1}"

ECS_CLUSTER="${ECS_CLUSTER:-$(terraform -chdir="$TERRAFORM_ROOT/bastion" output -raw cluster_name 2>/dev/null || true)}"
TASK_DEFINITION="${TASK_DEFINITION:-$(terraform -chdir="$TERRAFORM_ROOT/bastion" output -raw task_definition 2>/dev/null || true)}"
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-$(terraform -chdir="$TERRAFORM_ROOT/bastion" output -raw security_group_id 2>/dev/null || true)}"
ADMIN_BUCKET="${ADMIN_BUCKET:-$(terraform -chdir="$TERRAFORM_ROOT/bastion" output -raw admin_bucket 2>/dev/null || true)}"
SUBNET_ID="${SUBNET_ID:-$(terraform -chdir="$TERRAFORM_ROOT/shared" output -json private_subnet_ids 2>/dev/null | jq -r '.[0]' || true)}"

# ── Validate required vars ────────────────────────────────────────────────────

missing=()
for var in DATABASE_URL AWS_REGION ECS_CLUSTER TASK_DEFINITION SUBNET_ID SECURITY_GROUP_ID ADMIN_BUCKET; do
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

# ── Spin up bastion task ──────────────────────────────────────────────────────

SETUP_DB_URL=$(aws s3 presign "s3://${ADMIN_BUCKET}/setup-db.sql" --expires-in 300 --region "$AWS_REGION")

echo "Starting bastion task..."

# Append sslmode=require if not already present
if [[ "$DATABASE_URL" != *"sslmode="* ]]; then
  [[ "$DATABASE_URL" == *"?"* ]] && DATABASE_URL="${DATABASE_URL}&sslmode=require" \
                                 || DATABASE_URL="${DATABASE_URL}?sslmode=require"
fi

TASK_ARN=$(aws ecs run-task \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --task-definition "$TASK_DEFINITION" \
  --launch-type FARGATE \
  --enable-execute-command \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SECURITY_GROUP_ID],assignPublicIp=DISABLED}" \
  --query 'tasks[0].taskArn' \
  --output text)

if [[ -z "$TASK_ARN" || "$TASK_ARN" == "None" ]]; then
  echo "Error: failed to start task — check AWS credentials and permissions" >&2
  exit 1
fi

trap '
  echo ""
  echo "Stopping bastion task..."
  aws ecs stop-task \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER" \
    --task "$TASK_ARN" \
    --output text > /dev/null
  echo "Done."
' EXIT

echo "Task ARN: $TASK_ARN"
echo "Waiting for task to start (~30-60s)..."

aws ecs wait tasks-running \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --tasks "$TASK_ARN"

# SSM agent inside the container needs a few seconds to register after the task starts
sleep 5

echo "Connecting to database..."
echo "(Type \\q or exit to close session)"
echo ""

# ── Open psql session via ECS Exec ───────────────────────────────────────────

aws ecs execute-command \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --task "$TASK_ARN" \
  --container psql \
  --interactive \
  --command "/bin/sh -c '
    wget -qO setup-db.sql \"${SETUP_DB_URL}\" \
      && echo \"setup-db.sql downloaded — run: \\\\i setup-db.sql\"
    psql \"${DATABASE_URL}\"
    exec /bin/sh
  '"
