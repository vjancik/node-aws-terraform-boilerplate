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

### Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your github_org and github_repo
```

### Init

Run once after cloning, or after adding new providers/modules:

```bash
terraform init
```

### Plan (dry run)

Preview what Terraform will create, change, or destroy — no changes are applied:

```bash
terraform plan
```

### Apply

Create or update infrastructure:

```bash
terraform apply
```

Terraform will print the plan and prompt for confirmation before making any changes. After a successful apply, the ECR repository URL and GitHub Actions IAM role ARN are printed as outputs. Copy the role ARN to your GitHub repository secrets as `AWS_ROLE_ARN`.

### Tear down

Destroy all managed resources:

```bash
terraform destroy
```

## Backend endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/livez` | Liveness probe (Kubernetes) |
| GET | `/readyz` | Readiness probe (Kubernetes) |
| ALL | `/*` | Catch-all — returns `Ok` |
