# node-aws-terraform-example

A monorepo example project using pnpm workspaces + Turborepo, with a NestJS backend and a placeholder web app. Infrastructure is managed with Terraform targeting AWS EKS.

## Structure

```
apps/
  backend/   # NestJS HTTP server
  web/       # placeholder (unused)
```

## Prerequisites

- Node.js >= 18
- pnpm >= 10
- Turborepo (installed as a dev dependency — no global install needed)

## Setup

```bash
pnpm install
```

## Commands

All commands should be run from the **monorepo root** using `pnpm`. Turborepo orchestrates tasks across all packages, handling caching and ordering automatically.

### Development

```bash
pnpm dev        # start all apps in watch mode
```

To run a single app in dev mode:

```bash
pnpm --filter @repo/backend dev
```

### Build

```bash
pnpm build      # build all apps
```

Turborepo caches build outputs. Subsequent builds only recompile what has changed.

To build a single app:

```bash
pnpm --filter @repo/backend build
```

### Start (production)

```bash
pnpm start      # build then start all apps
```

### Adding dependencies

Always use `pnpm` with a `--filter` flag to add dependencies to a specific app — never run `npm install` or `yarn`:

```bash
# add a runtime dependency to backend
pnpm --filter @repo/backend add <package>

# add a dev dependency to backend
pnpm --filter @repo/backend add -D <package>

# add a dev dependency to the monorepo root (e.g. shared tooling)
pnpm add -D -w <package>
```

### Running arbitrary turbo tasks

```bash
pnpm turbo run <task>                        # run a task across all packages
pnpm turbo run <task> --filter=@repo/backend # run a task in one package only
```

## Deployment

Infrastructure is managed with Terraform in the `terraform/` directory. All commands below should be run from that directory.

### Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) >= 2
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5

### AWS authentication

Terraform uses the AWS CLI credentials chain. Log in before running any Terraform commands:

```bash
# SSO (recommended)
aws sso login --profile <your-profile>
export AWS_PROFILE=<your-profile>

# Or with an access key
aws configure
```

Verify the correct account is active:

```bash
aws sts get-caller-identity
```

### Layout

Terraform is split into independent root modules. Apply them in order:

```
terraform/
  shared/   # VPC, ECR, GitHub OIDC IAM — apply first, never destroy while other layers exist
  ecs/      # ECS Fargate cluster, ALB, ACM, auto scaling — depends on shared/
  modules/  # reusable modules, not applied directly
```

### Configure variables

Each root module has its own `terraform.tfvars`. Copy the example and fill in the values:

```bash
cp terraform/shared/terraform.tfvars.example terraform/shared/terraform.tfvars
cp terraform/ecs/terraform.tfvars.example terraform/ecs/terraform.tfvars
```

### Init

Run once per module after cloning, or after adding new providers/modules:

```bash
terraform -chdir=terraform/shared init
terraform -chdir=terraform/ecs init
```

### Plan (dry run)

Preview what Terraform will create, change, or destroy — no changes are applied:

```bash
terraform -chdir=terraform/shared plan
terraform -chdir=terraform/ecs plan
```

### Apply

Apply shared infrastructure first, then ECS:

```bash
terraform -chdir=terraform/shared apply
terraform -chdir=terraform/ecs apply
```

After applying `shared`, copy the `github_actions_role_arn` output to your GitHub repository secrets as `AWS_ROLE_ARN`.

After applying `ecs`, the outputs include:
- `alb_dns_name` — the ALB DNS name to use as a CNAME target in Cloudflare
- `acm_validation_records` — CNAME records to add in Cloudflare to validate the ACM certificate

Add both records in Cloudflare, then wait for ACM validation to complete (usually 1–2 minutes).

### Tear down

Destroy in reverse order — always destroy ECS before shared:

```bash
terraform -chdir=terraform/ecs destroy
terraform -chdir=terraform/shared destroy
```

## Backend endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/livez` | Liveness probe (Kubernetes) |
| GET | `/readyz` | Readiness probe (Kubernetes) |
| ALL | `/*` | Catch-all — returns `Ok` |
