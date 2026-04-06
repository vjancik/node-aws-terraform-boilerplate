# Load Testing

Load tests live here. Requires [k6](https://k6.io/docs/get-started/installation/).

## Running

```bash
# Basic run
K6_TARGET=https://api.yourdomain.com k6 run scripts/load-testing/fib.js

# With live dashboard at http://localhost:5665
K6_WEB_DASHBOARD=true K6_TARGET=https://api.yourdomain.com k6 run scripts/load-testing/fib.js

# With live dashboard + export HTML report on completion
K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=scripts/load-testing/results/report.html K6_TARGET=https://api.yourdomain.com k6 run scripts/load-testing/fib.js

# Higher CPU load (default FIB_N=38, max practical ~45)
K6_WEB_DASHBOARD=true K6_TARGET=https://api.yourdomain.com FIB_N=42 k6 run scripts/load-testing/fib.js
```

JSON results are saved to `results/` (gitignored). HTML reports are kept as reference examples.

## Test profile

30-minute run, 20 virtual users at peak, fibonacci workload — designed to peg CPU and observe autoscaling end-to-end:

| Phase | Duration | VUs | Purpose |
|-------|----------|-----|---------|
| Warm-up | 2m | 0 → 5 | Baseline latency |
| Ramp | 3m | 5 → 20 | Drive CPU past 60% threshold |
| Hold | 20m | 20 | Observe scale-out and stabilisation |
| Ramp down | 2m | 20 → 1 | Trigger scale-in cooldown |
| Idle | 3m | 0 | Confirm scale-in fires |

## Reference results

### [fib-ecs-report.html](results/fib-ecs-report.html) — ECS Fargate

ECS autoscaling is driven by a CloudWatch alarm on CPU utilisation. At 100% CPU load, the alarm takes **8–10 minutes** to trigger — CloudWatch metrics have a 1-minute resolution and ECS waits for several consecutive breaches before acting. New Fargate tasks then take another minute to start and register with the ALB.

### [fib-eks-report.html](results/fib-eks-report.html) — EKS + Karpenter

Karpenter watches for `Pending` pods directly and provisions EC2 nodes in **~1 minute**. Once the node is ready, new pods start in **30–60 seconds**. The latency improvement in the EKS report is noticeably faster than ECS — visible as a sharper drop in p95/p99 after the scale-out.
