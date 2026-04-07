# EKS Improvements Plan

Steps to be implemented one at a time and verified before moving to the next.
Check off each item as it's done.

---

## ~~Step 1 — Gateway API with ALB controller [x]~~

**Implemented.** Key notes from the actual implementation:

- ALB controller upgraded to `3.2.1` with `ALBGatewayAPI=true` feature gate
- Gateway API CRDs: use the **experimental channel** v1.5.1 (standard channel missing `ListenerSet` required by LBC 3.2.1):
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
  ```
- AWS LBC CRDs (`LoadBalancerConfiguration`, `TargetGroupConfiguration`) are installed automatically by the ALB controller Helm chart — no separate install needed
- `TargetGroupConfiguration` health check field names differ from Ingress annotation names: use `healthCheckPath`, `healthCheckPort`, `healthCheckProtocol`, `healthCheckInterval` (not `path`, `port`, `protocol`, `intervalSeconds`). `healthCheckPort` must be a string (quote it in Helm).
- SSL policy moved to `LoadBalancerConfiguration.spec.listenerConfigurations[].sslPolicy`
- HTTP→HTTPS redirect handled by a separate HTTPRoute on the `http` listener using `RequestRedirect` filter — no host matching needed (catch-all)
- `gateway.hosts` is a list — supports multiple subdomains on one ALB. ExternalDNS annotation uses comma-joined list: `{{ join "," .Values.gateway.hosts }}`
- ACM cert must be a **wildcard** (`*.yourdomain.com`) to cover all subdomains without re-validation per host

---

## ~~Step 2 — ExternalDNS with Cloudflare provider [x]~~

**Implemented.** Key notes from the actual implementation:

- ExternalDNS chart version `1.20.0`, source `gateway-httproute`, provider `cloudflare`
- Cloudflare token requires **Zone / DNS / Edit** permission scoped to the specific zone — no broader account permissions needed
- Token stored as a manual Kubernetes secret (not in Terraform state):
  ```bash
  kubectl create secret generic cloudflare-api-token \
    --from-literal=token=<CF_API_TOKEN> \
    -n kube-system
  ```
- ExternalDNS polls on ~1 minute interval — not event-driven. DNS records appear within 1 minute of HTTPRoute creation
- Also creates a `TXT` ownership record (`cname-<hostname>`) alongside each CNAME — used to track which records ExternalDNS owns (`upsert-only` policy means it never deletes)
- Multiple hostnames in one annotation: `{{ join "," .Values.gateway.hosts }}` — ExternalDNS creates one CNAME per hostname
- The CNAME points at the ALB hostname which is stable across helm deploys — only changes if the Gateway resource is recreated

---

## Step 3 — Pod Identity vs IRSA [ ]

**Why:** IRSA (IAM Roles for Service Accounts) uses the OIDC federation model — requires the OIDC provider Terraform resource, and role trust policies reference the OIDC issuer URL. Pod Identity is newer, simpler (trust policy just uses `pods.eks.amazonaws.com`), no OIDC provider resource needed. Both work. IRSA is not broken, so this is a simplification, not a bug fix.

**Current IRSA roles in our setup:**
- `vpc_cni` — IRSA (namespace: kube-system, SA: aws-node)
- `alb_controller` — IRSA (namespace: kube-system, SA: aws-load-balancer-controller)
- `karpenter_controller` — IRSA (namespace: kube-system, SA: karpenter)

**What Pod Identity requires differently:**
- Replace OIDC-based trust policy with `pods.eks.amazonaws.com` principal
- Add `aws_eks_pod_identity_association` resource linking the role to a namespace + SA
- The `eks-pod-identity-agent` addon is already installed in our cluster (`aws_eks_addon.pod_identity_agent` exists)
- Remove the OIDC federation trust condition entirely
- The `aws_iam_openid_connect_provider.eks` resource can be removed once all roles are migrated (the GHA OIDC provider in `shared/` is separate and stays)

**Trust policy change per role** (example for ALB controller):
```hcl
# Before (IRSA):
assume_role_policy = jsonencode({
  Statement = [{
    Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
    Action    = "sts:AssumeRoleWithWebIdentity"
    Condition = {
      StringEquals = {
        "${local.oidc_issuer_url}:aud" = "sts.amazonaws.com"
        "${local.oidc_issuer_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
      }
    }
  }]
})

# After (Pod Identity):
assume_role_policy = jsonencode({
  Statement = [{
    Principal = { Service = "pods.eks.amazonaws.com" }
    Action    = ["sts:AssumeRole", "sts:TagSession"]
  }]
})
```

**Pod Identity association** (one per role, replaces the SA annotation approach):
```hcl
resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn
}
```

**ServiceAccount annotation no longer needed** — remove `eks.amazonaws.com/role-arn` annotation from `kubernetes_service_account_v1.alb_controller` in `terraform/eks/main.tf`.

**Migration order:** Do one role at a time. After changing the trust policy + adding the association + removing the annotation, restart the affected pod and verify it can still reach AWS APIs.

**Karpenter note:** Karpenter uses the SA annotation approach via `serviceAccount.annotations` in the Helm values. With Pod Identity, remove that annotation from the Helm set values and add `aws_eks_pod_identity_association` instead.

**OIDC provider cleanup:** Only remove `aws_iam_openid_connect_provider.eks` after all three roles (vpc_cni, alb_controller, karpenter_controller) are migrated. The GHA OIDC in `shared/iam.tf` is a separate provider and is unaffected.

**Verify:** After migrating each role, check the controller logs for any AWS permission errors. For ALB controller: `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`. For Karpenter: `kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter`.

---

## Step 4 — WAF on the ALB [ ]

**Why:** No WAF currently. At minimum, the AWS Managed Rules (Core Rule Set) blocks common exploits (XSS, SQLi). Rate limiting prevents basic DDoS. Low config overhead for meaningful protection.

**What changes:**
- Add `aws_wafv2_web_acl` resource to `terraform/eks/main.tf`
- Reference WAF ARN in the `LoadBalancerConfiguration` (from Step 1)

**WAF resource** in `terraform/eks/main.tf`:
```hcl
resource "aws_wafv2_web_acl" "alb" {
  name  = "${var.name}-alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 3
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 10000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-alb-waf"
    sampled_requests_enabled   = true
  }
}

output "waf_acl_arn" {
  value = aws_wafv2_web_acl.alb.arn
}
```

**Wire WAF into the Gateway** — update `LoadBalancerConfiguration` in the Helm chart to include:
```yaml
spec:
  wafV2:
    webACL: {{ .Values.gateway.wafAclArn | quote }}
```

Add `gateway.wafAclArn` to `values.yaml` (populated from `terraform output waf_acl_arn` at deploy time, same as cert ARN today).

**Cost:** WAF WebACL = $5/month. Each managed rule group = $1/month. Two rule groups + one rate rule = ~$7/month total. Sampled requests logging is free.

**Verify:** After deploy, check AWS Console → WAF → Web ACLs — confirm it's associated with the ALB. Send a test SQL injection in a query param and confirm it's blocked (403).

---

## Step 5 — Container securityContext hardening [ ]

**Why:** Containers currently run with no securityContext — they could write to the filesystem, escalate privileges, or use Linux capabilities they don't need. Defence in depth with minimal operational impact.

**What changes:** Add `securityContext` to the container spec in `helm/backend/templates/deployment.yaml`.

```yaml
containers:
  - name: backend
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
```

**`readOnlyRootFilesystem: true` impact on NestJS:** Node.js writes to `/tmp` for some operations. Add a tmpfs emptyDir mount:
```yaml
volumeMounts:
  - name: tmp
    mountPath: /tmp
volumes:
  - name: tmp
    emptyDir:
      medium: Memory
```

Check if NestJS needs any other writable paths — the dist/ directory is read-only which is fine since it's already built. If the app writes anywhere else, add additional mounts.

**No CPU limits note:** We currently set `cpu: "1"` as a limit in values.yaml. Per the reference repo's reasoning (and our own load test observations), CPU limits cause kernel throttling at fractional values. Consider removing the CPU limit and keeping only the CPU request for scheduling. Memory limit stays (prevents OOM).

**Verify:** After deploy, confirm pods are Running. Test the `/fib/30` endpoint to ensure no filesystem permission errors at runtime. Check pod logs for any startup errors.

---

## ~~Step 6 — Control plane logging [x]~~

**Implemented.** Key notes from the actual implementation:

- `enabled_cluster_log_types` added to `aws_eks_cluster.main` in `terraform/modules/eks/main.tf` — in-place update, no downtime
- CloudWatch log group `/aws/eks/node-tf-eks/cluster` imported into Terraform state with 30-day retention (`aws_cloudwatch_log_group` resource in the same module). Without this, EKS creates the log group with no expiry and Terraform has no control over retention.
- Log group must be added to `depends_on` in `aws_eks_cluster.main` so it exists before the cluster tries to write to it
- Import command used: `terraform -chdir=terraform/eks import 'module.eks.aws_cloudwatch_log_group.eks_cluster' '/aws/eks/node-tf-eks/cluster'`
- Cost: effectively free for a small cluster — ingestion is $0.50/GB, a quiet cluster produces a few MB/day at most
