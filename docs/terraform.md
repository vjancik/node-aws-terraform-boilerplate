# Terraform Notes

## ENI pod density limit

Each EC2 instance has a hard limit on how many pod IPs it can assign, determined by the number of ENIs the instance supports and IPs per ENI:

```
max pods = (ENIs × IPs per ENI) - 1
```

For `t4g.small`: 3 ENIs × 4 IPs - 1 = **11 pods max**

This is an EC2 hardware limit, not a Kubernetes limit — it cannot be raised by changing Kubernetes config.

This limit only matters with `target-type: ip` (ALB routes directly to pod IPs). With `target-type: instance` the ALB routes to the node IP and only the node needs an ENI slot, so pod density is unconstrained by this limit.

### Solution: prefix delegation

Instead of assigning one IP per pod, the VPC CNI assigns a `/28` prefix (16 IPs) per ENI slot:

```
max pods = (ENIs × 16) - 1
```

For `t4g.small`: 3 × 16 - 1 = **47 pods**

Enable by setting `ENABLE_PREFIX_DELEGATION=true` on the VPC CNI addon. In Terraform, add to the `aws_eks_addon` resource for `vpc-cni`:

```hcl
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.vpc_cni.arn

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
    }
  })
}
```

Note: prefix delegation requires subnets to have enough IP space for `/28` blocks. A `/24` subnet (256 IPs) comfortably supports it.

## terraform init -upgrade

`terraform init` skips re-downloading providers and modules if they are already cached in `.terraform/`. Use `-upgrade` to force it to re-resolve versions and download the latest allowed by version constraints:

```bash
terraform -chdir=terraform/eks init -upgrade
```

Safe to run at any time — it does not modify state or apply anything. Use it when:
- Adding a new provider or module
- Bumping a version constraint and wanting the new version pulled immediately
- A provider download is stale or corrupted
