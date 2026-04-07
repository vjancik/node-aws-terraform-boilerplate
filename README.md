# Node AWS Terraform Boilerplate (WIP)

A monorepo example project using pnpm workspaces + Turborepo, with a NestJS backend and a placeholder web app. Infrastructure is managed with Terraform targeting AWS EKS (with Helm) or ECS.

## Table of Contents

- [Structure](#structure)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Commands](#commands)
  - [Development](#development)
  - [Build](#build)
  - [Start (production)](#start-production)
  - [Adding dependencies](#adding-dependencies)
  - [Running arbitrary turbo tasks](#running-arbitrary-turbo-tasks)
- [Deployment](#deployment)
  - [Prerequisites](#prerequisites-1)
  - [AWS authentication](#aws-authentication)
  - [Layout](#layout)
  - [Configure variables](#configure-variables)
  - [Init](#init)
  - [Plan (dry run)](#plan-dry-run)
  - [Apply](#apply)
  - [Tear down](#tear-down)
- [Load testing](#load-testing)
- [Further reading](#further-reading)
- [Backend endpoints](#backend-endpoints)

## Structure

```
apps/
  backend/       # NestJS HTTP server
  web/           # placeholder (unused)
docs/
  kubernetes.md  # Karpenter, autoscaling, Gateway API notes
  terraform.md   # ENI limits, two-pass apply, init flags
  todo.md        # planned improvements
helm/
  backend/       # Helm chart for the backend app (EKS)
scripts/
  load-testing/  # k6 load test scripts and HTML reports
terraform/
  shared/        # VPC, ECR, GitHub OIDC — shared between ECS and EKS
  ecs/           # ECS Fargate stack
  eks/           # EKS + Karpenter stack
  modules/
    ecs/         # ECS module
    eks/         # EKS module
    networking/  # VPC, subnets, NAT gateway
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
  eks/      # EKS cluster, Karpenter, ALB controller, ExternalDNS, metrics-server — depends on shared/
  modules/  # reusable modules, not applied directly
```

### Configure variables

Each root module has its own `terraform.tfvars`. Copy the example and fill in the values:

```bash
cp terraform/shared/terraform.tfvars.example terraform/shared/terraform.tfvars
cp terraform/ecs/terraform.tfvars.example terraform/ecs/terraform.tfvars
cp terraform/eks/terraform.tfvars.example terraform/eks/terraform.tfvars
```

### Init

Run once per module after cloning, or after adding new providers/modules:

```bash
terraform -chdir=terraform/shared init
terraform -chdir=terraform/ecs init
terraform -chdir=terraform/eks init
```

### Plan (dry run)

Preview what Terraform will create, change, or destroy — no changes are applied:

```bash
terraform -chdir=terraform/shared plan
terraform -chdir=terraform/ecs plan
terraform -chdir=terraform/eks plan
```

### Apply

Apply shared infrastructure first:

```bash
terraform -chdir=terraform/shared apply
```

After applying `shared`, copy the `github_actions_role_arn` output to your GitHub repository secrets as `AWS_ROLE_ARN`.

Then apply ECS or EKS — both require a two-pass apply, see the sections below for the exact commands.

#### Route 53 managed domains (optional)

If your domain is managed in Route 53, Terraform can handle ACM validation and ALB DNS records automatically — eliminating the two-pass apply requirement entirely.

Add a `route53_zone_id` variable to both `terraform/ecs/variables.tf` and `terraform/eks/variables.tf`, then add the following to each module:

```hcl
# ACM validation record — created automatically, no manual DNS step
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => dvo
  }

  zone_id = var.route53_zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

# ALB CNAME — points your domain at the ALB automatically
resource "aws_route53_record" "alb" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name  # or module.ecs.alb_dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
```

With Route 53, ECS `terraform apply` completes in a single pass with no manual DNS steps. EKS uses ExternalDNS for DNS management (see below) and still requires two passes due to the Karpenter CRD requirement.

#### ECS: two-pass apply required

`terraform apply` will block indefinitely on `aws_acm_certificate_validation` until the DNS validation CNAME exists — but the CNAME values are only available after the certificate is created. Apply in two passes:

```bash
# Pass 1: everything except the ACM validation wait and HTTPS listener
terraform -chdir=terraform/ecs apply \
  -target=module.ecs.aws_acm_certificate.main \
  -target=module.ecs.aws_lb.main \
  -target=module.ecs.aws_lb_listener.http \
  -target=module.ecs.aws_lb_target_group.backend
```

Fetch the validation CNAME from the output:

```bash
terraform -chdir=terraform/ecs output
# or directly:
aws acm describe-certificate \
  --certificate-arn <arn> \
  --region us-east-1 \
  --query "Certificate.DomainValidationOptions"
```

Add the CNAME to your domain DNS provider (set proxy status to **DNS only**, not proxied), then wait for ACM validation to complete (usually 1–2 minutes).

```bash
# Pass 2: remaining resources (HTTPS listener, ECS service, auto scaling)
terraform -chdir=terraform/ecs apply
```

After applying `ecs`, add the ALB DNS name as a CNAME for your domain in your DNS provider.

#### EKS: two-pass apply required

The Karpenter `NodePool` and `EC2NodeClass` resources are Kubernetes CRDs installed by the Karpenter Helm chart. The `kubernetes_manifest` Terraform resources that create them require the CRDs to already exist in the cluster API at **plan time**, not just apply time — so they cannot be created in the same pass as the Helm chart itself.

Apply in two passes:

```bash
# Pass 1: cluster + Helm charts (metrics-server, ALB controller, Karpenter)
terraform -chdir=terraform/eks apply \
  -target=module.eks \
  -target=aws_ec2_tag.public_subnet_eks \
  -target=aws_ec2_tag.public_subnet_cluster \
  -target=aws_ec2_tag.private_subnet_internal_elb \
  -target=aws_ec2_tag.private_subnet_cluster \
  -target=aws_acm_certificate.main \
  -target=helm_release.metrics_server \
  -target=kubernetes_service_account_v1.alb_controller \
  -target=helm_release.alb_controller \
  -target=helm_release.karpenter

# Pass 2: Karpenter NodePool + EC2NodeClass (CRDs now registered)
terraform -chdir=terraform/eks apply
```

After applying `eks`, add these secrets to your GitHub repository:

| Secret | Value |
|--------|-------|
| `AWS_EKS_ROLE_ARN` | `github_actions_eks_deploy_role_arn` output |
| `EKS_ACM_CERT_ARN` | `acm_certificate_arn` output |
| `EKS_DOMAIN_NAME` | e.g. `api.yourdomain.com` |

Then update kubeconfig locally to use kubectl against the cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name node-tf-eks
```

#### ExternalDNS + Cloudflare setup (EKS only)

EKS uses [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) with the Cloudflare provider to automatically create and update DNS records whenever a Gateway HTTPRoute is deployed. No manual CNAME management is needed after initial setup.

**ACM certificate:** Use a wildcard certificate (`*.yourdomain.com`) rather than a per-subdomain cert. This allows ExternalDNS to add any subdomain to the HTTPRoute without requiring a new cert or re-validation. Set `domain_name = "*.yourdomain.com"` in `terraform/eks/terraform.tfvars`. The wildcard validation CNAME only needs to be added to your DNS provider once.

**Cloudflare API token:** Create a token with **Zone / DNS / Edit** permission scoped to your zone (Cloudflare dashboard → My Profile → API Tokens). Then create a Kubernetes secret (do not commit the token):

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=token=<CF_API_TOKEN> \
  -n kube-system
```

After deploying the Helm chart, ExternalDNS automatically creates a CNAME record in Cloudflare pointing each hostname in the HTTPRoute at the ALB address. Verify:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=20
kubectl get gateway backend-gateway
```

#### Changing the domain name

Updating `domain_name` in `terraform.tfvars` replaces the ACM certificate (`create_before_destroy` ensures no gap). Since ACM validation is required again, apply in two passes — same pattern as initial setup.

**ECS:**

```bash
# Pass 1: replace the certificate
terraform -chdir=terraform/ecs apply -target=module.ecs.aws_acm_certificate.main

# Add the validation CNAME from the output to your DNS provider
terraform -chdir=terraform/ecs output

# Pass 2: update HTTPS listener to use new cert + everything else
terraform -chdir=terraform/ecs apply
```

Then update your DNS CNAME for the new subdomain to point at the ALB DNS name.

**EKS:**

```bash
# Pass 1: replace the certificate
terraform -chdir=terraform/eks apply -target=aws_acm_certificate.main

# Add the validation CNAME from the output to your DNS provider
terraform -chdir=terraform/eks output

# Pass 2: everything else (Gateway picks up new cert ARN automatically)
terraform -chdir=terraform/eks apply
```

Then update `EKS_ACM_CERT_ARN` GitHub secret to the new value. ExternalDNS handles the DNS CNAME automatically.

### Tear down

Destroy in reverse order — always destroy ECS/EKS before shared:

```bash
terraform -chdir=terraform/ecs destroy
terraform -chdir=terraform/eks destroy
terraform -chdir=terraform/shared destroy
```

## Load testing

See [scripts/load-testing/README.md](scripts/load-testing/README.md) for run commands, test profile, and reference results comparing ECS and EKS autoscaling behaviour.

## Further reading

- [docs/kubernetes.md](docs/kubernetes.md) — Karpenter debugging, node autoscaling trade-offs, Gateway API conflict detection
- [docs/terraform.md](docs/terraform.md) — ENI pod density limits, prefix delegation, terraform init -upgrade
- [docs/managed-kubernetes-cost-analysis.md](docs/managed-kubernetes-cost-analysis.md) — EKS vs GKE vs AKS cost comparison, NAT gateway, load balancer alternatives
- [docs/container-hardening.md](docs/container-hardening.md) — securityContext settings, Docker Compose equivalents, readOnlyRootFilesystem notes
- [docs/todo.md](docs/todo.md) — Planned improvements

## Backend endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/fib/:n` | Compute fibonacci(n), capped at 42, runs in a worker thread |
| GET | `/livez` | Liveness probe (Kubernetes) |
| GET | `/readyz` | Readiness probe (Kubernetes) |
| ALL | `/*` | Catch-all — returns `Ok` |
