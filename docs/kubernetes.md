# Kubernetes Notes

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
