# EKS Improvements Plan

Steps to be implemented one at a time and verified before moving to the next.
Check off each item as it's done.

---

## Step 1 — Gateway API with ALB controller [ ]

**Why:** Current setup uses the classic Kubernetes `Ingress` API with ALB annotations. Gateway API is the official successor, allows multiple services to share one ALB via multiple `HTTPRoute` resources attached to a single `Gateway`, and is required for any future Envoy Gateway hybrid setup.

**What changes:**
- Enable Gateway API feature gate on the ALB controller (`ALBGatewayAPI=true`)
- Install Gateway API CRDs (standard channel)
- Add two new AWS LBC CRDs: `LoadBalancerConfiguration`, `TargetGroupConfiguration`
- Replace `helm/backend/templates/ingress.yaml` (Ingress) with three new manifests:
  - `gatewayclass.yaml` — cluster-scoped, created once
  - `gateway.yaml` — one per cluster (or moved to Terraform)
  - `httproute.yaml` — one per service, replaces Ingress rules
- Remove `ingress.*` values from `helm/backend/values.yaml`; add `gateway.*` values

**ALB controller change** in `terraform/eks/main.tf` — add feature gate:
```hcl
{ name = "controllerConfig.featureGates.ALBGatewayAPI", value = "true" }
```

**Install Gateway API CRDs** (run once after Terraform apply, before helm deploy):
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

**Install AWS LBC Gateway API CRDs** (LoadBalancerConfiguration + TargetGroupConfiguration):
```bash
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
```

**GatewayClass manifest** (`helm/backend/templates/gatewayclass.yaml`):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: aws-lb-controller
spec:
  controllerName: gateway.k8s.aws/alb
```
Note: GatewayClass is cluster-scoped. If we later add more services, they reuse this same GatewayClass. Consider moving it out of the backend Helm chart into a separate cluster-config chart or applying it once via kubectl.

**LoadBalancerConfiguration** (`helm/backend/templates/lbconfig.yaml`):
```yaml
apiVersion: gateway.k8s.aws/v1beta1
kind: LoadBalancerConfiguration
metadata:
  name: backend-alb-config
spec:
  scheme: internet-facing
  listenerConfigurations:
    - protocolPort: HTTPS:443
      defaultCertificate: {{ .Values.gateway.certificateArn | quote }}
```

**Gateway manifest** (`helm/backend/templates/gateway.yaml`):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: backend-gateway
spec:
  gatewayClassName: aws-lb-controller
  infrastructure:
    parametersRef:
      group: gateway.k8s.aws
      kind: LoadBalancerConfiguration
      name: backend-alb-config
  listeners:
    - name: http
      protocol: HTTP
      port: 80
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: Same
```

**HTTPRoute manifest** (`helm/backend/templates/httproute.yaml`):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .Release.Name }}
spec:
  hostnames:
    - {{ .Values.gateway.host | quote }}
  parentRefs:
    - name: backend-gateway
      sectionName: https
  rules:
    - backendRefs:
        - name: {{ .Release.Name }}
          port: {{ .Values.service.port }}
```

**TargetGroupConfiguration** (`helm/backend/templates/targetgroupconfig.yaml`):
```yaml
apiVersion: gateway.k8s.aws/v1beta1
kind: TargetGroupConfiguration
metadata:
  name: {{ .Release.Name }}-tgc
spec:
  targetReference:
    kind: Service
    name: {{ .Release.Name }}
  defaultConfiguration:
    targetType: ip
    healthCheckConfig:
      path: /readyz
      port: {{ .Values.service.port }}
      protocol: HTTP
      healthyThresholdCount: 2
      unhealthyThresholdCount: 3
      intervalSeconds: 30
```

Note: The HTTP→HTTPS redirect (`ssl-redirect: "443"`) currently set as an Ingress annotation needs to move to a separate HTTPRoute on the http listener that redirects to https. Add a redirect rule to the http listener's HTTPRoute.

**values.yaml changes:** rename `ingress.*` to `gateway.*`:
```yaml
gateway:
  certificateArn: ""
  host: ""
```

**Verify:** After deploy, `kubectl get gateway backend-gateway` shows `PROGRAMMED = True` and an ADDRESS. Hit both HTTP (should redirect) and HTTPS endpoints.

The old Ingress-provisioned ALB is deleted automatically when the Ingress resource is removed. The new Gateway-provisioned ALB takes its place. Update the DNS CNAME to the new ALB address.

---

## Step 2 — ExternalDNS with Cloudflare provider [ ]

**Why:** Currently, getting the ALB DNS name requires running `kubectl get ingress backend` and manually adding/updating a CNAME in Cloudflare. ExternalDNS automates this — it watches the Gateway resource and creates/updates the Cloudflare DNS record automatically on every deploy.

**What changes:**
- Add ExternalDNS Helm release to `terraform/eks/main.tf`
- Add IAM role for ExternalDNS (needs no AWS DNS permissions — Cloudflare provider uses an API token instead)
- Create a Cloudflare API token with Zone:DNS:Edit permission scoped to your zone
- Store the token as a Kubernetes secret (created once manually or via Terraform `kubernetes_secret`)
- Annotate the HTTPRoute with `external-dns.alpha.kubernetes.io/hostname` so ExternalDNS knows which domain to register

**ExternalDNS Helm release** in `terraform/eks/main.tf`:
```hcl
resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.16.1"  # check latest

  set = [
    { name = "provider",                                value = "cloudflare" },
    { name = "env[0].name",                             value = "CF_API_TOKEN" },
    { name = "env[0].valueFrom.secretKeyRef.name",      value = "cloudflare-api-token" },
    { name = "env[0].valueFrom.secretKeyRef.key",       value = "token" },
    { name = "sources[0]",                              value = "gateway-httproute" },
    { name = "policy",                                  value = "upsert-only" },
    { name = "txtOwnerId",                              value = "eks-node-tf" },
  ]

  depends_on = [module.eks]
}
```

**Cloudflare secret** (create once — do not commit the token):
```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=token=<CF_API_TOKEN> \
  -n kube-system
```

Or manage via Terraform `kubernetes_secret` with a `sensitive` variable.

**HTTPRoute annotation** (add to `helm/backend/templates/httproute.yaml`):
```yaml
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: {{ .Values.gateway.host | quote }}
```

**Policy `upsert-only`** means ExternalDNS will create and update records but never delete them. This is safe default behaviour — manual cleanup if you decommission a service.

**Verify:** After deploy, wait ~1 minute. Check Cloudflare DNS dashboard — the A/CNAME record for your domain should appear pointing at the new ALB address. `nslookup <domain>` to confirm propagation.

After this step, the manual CNAME update on every deploy is no longer needed.

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

**Why:** Currently no EKS control plane logs are sent to CloudWatch. These are essential for security incident investigation (who called what API, authentication events). The sample repo enables all five log types.

**Cost:** EKS control plane logs go to CloudWatch Logs. The data ingestion cost is $0.50/GB. For a small cluster with low API activity, this is typically **under $1/month** and often rounds to a few cents. CloudWatch log storage is $0.03/GB/month after the free tier (5GB free). Effectively free for a small cluster.

**What changes:** Add `enabled_cluster_log_types` to `aws_eks_cluster.main` in `terraform/modules/eks/main.tf`:

```hcl
resource "aws_eks_cluster" "main" {
  ...
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  ...
}
```

This is an in-place update — no cluster replacement, no downtime. Terraform will update the cluster configuration directly.

Logs appear in CloudWatch under `/aws/eks/<cluster-name>/cluster`.

**Verify:** After `terraform apply`, go to CloudWatch → Log groups → `/aws/eks/node-tf-eks/cluster`. You should see log streams for each component. Run `kubectl get nodes` and confirm an API log entry appears.
