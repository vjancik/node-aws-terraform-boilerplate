# AWS Setup Notes

## Secrets Management

App secrets (OAuth credentials, database URL, auth keys) are stored in AWS Secrets Manager and injected into containers at runtime. Terraform creates the secret *resources* but does **not** manage the secret *values* — populate them manually after the first `terraform apply`.

### Secret paths

| Path | Used by |
|---|---|
| `/node-tf/web` | Web (Next.js) container — ECS + EKS |
| `/node-tf/backend` | Backend (NestJS) container — ECS + EKS |

> **Note:** ECS and EKS cannot work simultaneously with this setup. `BETTER_AUTH_URL` must point to the app's public URL, which differs between ECS and EKS (different domains). Since both stacks share the same `/node-tf/web` secret, only one can have the correct value at a time. To support both simultaneously, split into separate secrets (e.g. `/node-tf/ecs/web` and `/node-tf/eks/web`) and update the `secret_arn_web` references in each stack's Terraform accordingly.

### How to populate secrets

Each secret is a single JSON object whose keys map directly to environment variable names.

**Web secret** (`/node-tf/web`):

```bash
aws secretsmanager put-secret-value \
  --secret-id /node-tf/web \
  --secret-string '{
    "DATABASE_URL":          "postgresql://user:pass@host:5432/db",
    "BETTER_AUTH_SECRET":    "<random 32+ byte base64 string>",
    "BETTER_AUTH_URL":       "https://yourdomain.com",
    "GITHUB_CLIENT_ID":      "...",
    "GITHUB_CLIENT_SECRET":  "...",
    "GOOGLE_CLIENT_ID":      "...",
    "GOOGLE_CLIENT_SECRET":  "...",
    "DISCORD_CLIENT_ID":     "...",
    "DISCORD_CLIENT_SECRET": "..."
  }'
```

**Backend secret** (`/node-tf/backend`):

```bash
aws secretsmanager put-secret-value \
  --secret-id /node-tf/backend \
  --secret-string '{
    "DATABASE_URL": "postgresql://user:pass@host:5432/db"
  }'
```

To update a single key without replacing the whole object, use `--secret-string` with the full updated JSON (Secrets Manager replaces the entire value, not individual keys).

To verify what's currently stored:

```bash
aws secretsmanager get-secret-value --secret-id /node-tf/web --query SecretString --output text | jq keys
```

---

## How secrets reach containers

### ECS

The ECS agent reads the secret at container start and injects each JSON key as an individual environment variable. This happens before the container process starts — no app code changes needed.

The task execution role (`ecs-task-execution`) has `secretsmanager:GetSecretValue` scoped to the two secret ARNs. If a secret key is missing or the secret doesn't exist, the task will fail to start with an error visible in CloudWatch.

### EKS (External Secrets Operator)

ESO watches `ExternalSecret` CRDs (one per Helm chart) and reconciles them into native Kubernetes Secrets on a 1h refresh interval. Pods consume the K8s Secret via `envFrom: secretRef` — no awareness of ESO or AWS at the pod level.

**Auth**: ESO uses EKS Pod Identity (not static IAM keys). The `external-secrets` service account in the `external-secrets` namespace is bound to the `<cluster>-eks-eso` IAM role via `aws_eks_pod_identity_association`.

**Override the Secrets Manager key** (e.g. for a different environment):

```bash
helm upgrade web ./helm/web \
  --set secrets.secretManagerKey=/node-tf/web \
  ...
```

**Check sync status**:

```bash
kubectl get externalsecret -A
kubectl describe externalsecret web-secrets
```

A `SecretSyncedError` condition means ESO couldn't read the secret — check IAM permissions and that the secret value has been populated.

**Force a refresh** (without waiting for the 1h interval):

```bash
kubectl annotate externalsecret web-secrets \
  force-sync=$(date +%s) --overwrite
```

---

## Rotating secrets

1. Update the secret value in Secrets Manager (`aws secretsmanager put-secret-value ...`)
2. **ECS**: force a new deployment so tasks restart and pick up the new value:
   ```bash
   aws ecs update-service --cluster node-tf-ecs --service node-tf-ecs-web --force-new-deployment
   ```
3. **EKS**: ESO will sync the new value within the refresh interval (default 1h). Force an immediate sync with the annotate command above, then perform a rolling restart:
   ```bash
   kubectl rollout restart deployment/web
   ```
