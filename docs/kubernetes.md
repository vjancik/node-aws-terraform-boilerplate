# Kubernetes Notes

## Useful extensions of current setup

These are not implemented but are well-understood patterns worth adding as the project grows.

### Secrets Store CSI Driver

Mounts AWS Secrets Manager secrets directly into pods as files or env vars, without storing values in Helm `--set` flags or Kubernetes Secrets. The driver syncs the secret from AWS at pod start and optionally creates a K8s Secret object for env var access.

Requires two Helm charts: `secrets-store-csi-driver` (base) + `secrets-store-csi-driver-provider-aws` (AWS provider). A `SecretProviderClass` CRD maps a Secrets Manager secret to a volume mount:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: my-app-secrets
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "my-app/prod"
        objectType: "secretsmanager"
        jmesPath:
          - path: username
            objectAlias: DB_USER
          - path: password
            objectAlias: DB_PASS
  secretObjects:
    - secretName: my-app-secret
      type: Opaque
      data:
        - objectName: DB_USER
          key: username
        - objectName: DB_PASS
          key: password
```

The pod mounts the CSI volume and references the synced K8s Secret as env vars. The app service account needs a Pod Identity association with `secretsmanager:GetSecretValue` + `secretsmanager:DescribeSecret` on the secret ARN.

**When to add:** When secrets need rotation (CSI driver re-fetches on pod restart), or when avoiding secrets in CI/CD pipeline state is a requirement.

### EBS and EFS storage

**EBS CSI Driver** (`aws-ebs-csi-driver` EKS addon) is required for `PersistentVolumeClaim` with `ReadWriteOnce` access — the default `gp2` storage class was removed in EKS 1.30 and must be explicitly defined. Needed for StatefulSets (e.g. a self-hosted database pod). EBS volumes are AZ-scoped — a pod and its volume must be in the same AZ.

**EFS CSI Driver** (`aws-efs-csi-driver` EKS addon) enables `ReadWriteMany` — multiple pods across AZs mounting the same filesystem simultaneously. Useful for shared uploads, session storage, or any workload that needs a shared writable volume. EFS is elastic (no capacity to declare) and billed per GB stored.

Both drivers use Pod Identity for IAM access. EFS also requires mount targets in each subnet and uses the cluster security group for network access.

**When to add:** EBS CSI when adding StatefulSets or a database layer. EFS when multiple pods need to share writable storage.

### HPA dual-metric autoscaling

Our HPA currently scales on CPU only. Adding memory as a second metric catches Node.js workloads that balloon memory before CPU spikes:

```yaml
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70
```

HPA scales out when either threshold is breached. No additional infrastructure required — metrics-server already provides both.

**When to add:** If memory usage is a scaling signal for your workload (common for Node.js, JVM apps).

### RBAC ClusterRoles for team access

Kubernetes RBAC controls what `kubectl` operations an authenticated identity can perform. The chain is:

```
IAM Role → EKS Access Entry → Kubernetes Group → ClusterRoleBinding → ClusterRole
```

A read-only `viewer` role for developers:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: viewer
rules:
  - apiGroups: ["", "apps"]
    resources: ["pods", "deployments", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: viewer-binding
subjects:
  - kind: Group
    name: my-viewer   # matches EKS access entry group
roleRef:
  kind: ClusterRole
  name: viewer
  apiGroup: rbac.authorization.k8s.io
```

On the Terraform side, an `aws_eks_access_entry` maps the developer's IAM role to the `my-viewer` Kubernetes group. They can then `aws eks update-kubeconfig` and run read-only `kubectl` commands.

**When to add:** When more than one person needs cluster access with different permission levels.

### Namespace resource quotas

Hard ceilings on CPU, memory, and pod count per namespace — prevents one service from starving others on a shared cluster:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: default-quota
  namespace: my-service
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
```

Requires all pods in the namespace to declare resource `requests` and `limits` — quota enforcement fails open if pods omit them. Pair with a `LimitRange` to set defaults so pods without explicit requests still count against the quota.

**When to add:** When multiple teams or services share the same cluster and cost/stability isolation is needed.

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

## Karpenter debugging

If nodes aren't provisioning after deploy, check the Karpenter controller logs first — IAM `AccessDenied` errors and scheduling failures show up immediately:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter
```

Common causes:
- **AccessDenied** — IAM policy in `terraform/modules/eks/iam.tf` is stale for the installed Karpenter version. Check the [Karpenter upgrade guide](https://karpenter.sh/docs/upgrading/upgrade-guide/) for required IAM changes.
- **No instances launching** — NodePool resource limits exhausted, or no instance type in the NodePool fits the pending pod's requests
- **Pending pods not triggering Karpenter** — EC2NodeClass subnet/security group selector tags don't match the tags on the VPC resources

## Gateway API vs Ingress — conflict detection

With the classic **Ingress API**, path conflicts between multiple Ingress resources sharing the same ALB group (`alb.ingress.kubernetes.io/group.name`) are silently resolved by the ALB controller picking a winner arbitrarily. No error, no status condition, no programmatic way to detect it — you'd have to hit the endpoint and check which service responds.

**Gateway API** makes conflict resolution explicit and observable. A conflicting `HTTPRoute` is rejected with a status condition, the existing route keeps working, and no traffic is disrupted.

## Gateway API — HTTPRoute conflict detection

Gateway API conflict resolution is handled asynchronously by the ALB controller after `helm upgrade` or `kubectl apply` returns. Both commands succeed even if there's a path conflict — the controller rejects the conflicting route via a status condition, not an error.

Check post-apply:

```bash
kubectl get httproute
kubectl describe httproute <name>  # shows status conditions
```

A rejected route looks like:

```yaml
status:
  parents:
    - conditions:
      - type: Accepted
        status: "False"
        reason: "PathConflict"
        message: "Path /api already claimed by httproute/auth-service"
```

The existing route keeps working — no traffic disruption. The conflicting route is silently dropped until the conflict is resolved.

### Catching conflicts in CI

Add a post-deploy step to the GHA workflow after `helm upgrade`:

```bash
kubectl wait httproute/<name> \
  --for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' \
  --timeout=60s
```

Fails the pipeline if the route isn't accepted within 60s, same way `--atomic` catches pod health issues.
