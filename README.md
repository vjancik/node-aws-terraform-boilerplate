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
  eks/      # EKS cluster, Karpenter, ALB controller, metrics-server — depends on shared/
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

Apply shared infrastructure first, then ECS or EKS:

```bash
terraform -chdir=terraform/shared apply
terraform -chdir=terraform/ecs apply   # ECS path
terraform -chdir=terraform/eks apply   # EKS path
```

After applying `shared`, copy the `github_actions_role_arn` output to your GitHub repository secrets as `AWS_ROLE_ARN`.

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

With Route 53, `terraform apply` completes in a single pass with no manual DNS steps.

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

# Pass 2: everything else (Ingress annotation picks up new cert ARN automatically)
terraform -chdir=terraform/eks apply
```

Then update `EKS_ACM_CERT_ARN` and `EKS_DOMAIN_NAME` GitHub secrets to the new values, and update your DNS CNAME for the new subdomain to point at the ALB DNS name.

### Tear down

Destroy in reverse order — always destroy ECS/EKS before shared:

```bash
terraform -chdir=terraform/ecs destroy
terraform -chdir=terraform/eks destroy
terraform -chdir=terraform/shared destroy
```

## Load testing

Load tests live in `scripts/load-testing/`. Requires [k6](https://k6.io/docs/get-started/installation/).

```bash
# Basic run
K6_TARGET=https://api.yourdomain.com k6 run scripts/load-testing/fib.js

# With live dashboard at http://localhost:5665
K6_WEB_DASHBOARD=true K6_TARGET=https://api.yourdomain.com k6 run scripts/load-testing/fib.js

# With live dashboard + export HTML report on completion
K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=html-report.html K6_TARGET=https://api.yourdomain.com k6 run scripts/load-testing/fib.js

# Higher CPU load (default FIB_N=30, max practical ~45)
K6_WEB_DASHBOARD=true K6_TARGET=https://api.yourdomain.com FIB_N=40 k6 run scripts/load-testing/fib.js
```

Results are saved as JSON to `scripts/load-testing/results/` (gitignored).

## Node autoscaling — Karpenter vs alternatives

This project uses Karpenter for EKS node autoscaling. Here's how it compares to the alternatives:

### Karpenter (what we use)
- Watches for `Pending` pods and provisions nodes in ~30s
- Picks the cheapest instance type from a broad pool at launch time — including spot pricing
- Bin-packs pods optimally across instance types and AZs
- Consolidates underutilized nodes automatically
- AWS-specific (Azure support exists but lags)
- GA since 2023 — newer, less battle-tested than Cluster Autoscaler

### Cluster Autoscaler
- The traditional approach, been around since 2016
- Works by scaling predefined Auto Scaling Groups up/down
- Slower (~3-5 min vs ~30s) — polls ASG on a timer rather than watching pod events
- Instance types fixed at ASG definition time — no dynamic selection
- Multi-cloud — works on GKE, AKS, EKS with provider plugins
- Vastly more documentation and production mileage

### EKS Auto Mode / GKE Autopilot
- Fully managed by the cloud provider — no Karpenter or Cluster Autoscaler to configure
- AWS/GCP handle node provisioning, AMI updates, bin-packing automatically
- Less control, potentially higher cost (management premium)
- Best for teams that want zero node operational overhead

### Static node groups
- No autoscaling — fixed number of nodes, scale manually when needed
- Simplest possible setup, surprisingly common for small stable workloads
- No cold-start latency, predictable cost
- Wasteful under variable load

### When Karpenter is worth it
Karpenter pays off when you have variable load and care about cost — the spot instance bin-packing alone can cut node costs by 60-70%. For a fixed, stable workload, static nodes or Cluster Autoscaler are simpler and equally effective.

## Backend endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/livez` | Liveness probe (Kubernetes) |
| GET | `/readyz` | Readiness probe (Kubernetes) |
| ALL | `/*` | Catch-all — returns `Ok` |
