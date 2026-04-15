# ── App Secrets (AWS Secrets Manager) ─────────────────────────────────────────
# Secrets are created here (shared) so both ECS and EKS reference the same ARNs.
# Secret *values* are NOT managed by Terraform — populate them manually after
# first apply. See docs/aws.md for instructions.

# Web app secret — holds all env vars required by the Next.js container.
resource "aws_secretsmanager_secret" "web" {
  name                    = "/node-tf/web"
  description             = "Environment secrets for the web (Next.js) container"
  recovery_window_in_days = 7
}

# Backend secret — holds DATABASE_URL (and any future backend-specific secrets).
resource "aws_secretsmanager_secret" "backend" {
  name                    = "/node-tf/backend"
  description             = "Environment secrets for the backend (NestJS) container"
  recovery_window_in_days = 7
}
