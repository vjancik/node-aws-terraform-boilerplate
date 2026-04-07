# Managed Kubernetes Cost Analysis

Rough cost comparison for running a small Kubernetes cluster across the top 3 cloud providers. Figures are estimates accurate to approximately Q2 2025 — check current pricing pages before making decisions. GA availability of specific features may have changed.

## Control plane

| Provider | Cost | Notes |
|----------|------|-------|
| **EKS (AWS)** | $73/month per cluster | Flat fee regardless of size |
| **GKE (GCP)** | Free for first cluster, $73/month after | Best managed K8s — Google invented Kubernetes |
| **AKS (Azure)** | Free | Azure's competitive move; worker node pricing is higher to compensate |

**Takeaway:** For a single cluster, GKE is free and AKS is free. EKS charges $73/month before a single pod runs.

## NAT Gateway

Private subnets require a NAT gateway for outbound internet access. For a typical setup with 2 private subnets sharing one NAT gateway:

| Provider | Fixed cost | Data processing |
|----------|-----------|-----------------|
| **AWS** | ~$32/month per gateway | $0.045/GB |
| **GCP (Cloud NAT)** | $0 — no hourly fee | ~$0.045/GB |
| **Azure** | ~$32/month per gateway | $0.045/GB |

GCP Cloud NAT has no fixed hourly charge — for low-traffic workloads it's nearly free. AWS and Azure both charge a fixed ~$32/month per gateway regardless of usage.

## Egress bandwidth

| Provider | Cost |
|----------|------|
| **AWS** | $0.09/GB (first 10TB) |
| **GCP** | $0.08/GB, drops faster at volume |
| **Azure** | $0.087/GB (first 10GB), then $0.083/GB |

All three are roughly similar. GCP has a slight edge at volume.

## Total baseline cost (small cluster, 1 NAT gateway)

| Provider | Control plane | NAT gateway | Total baseline |
|----------|--------------|-------------|----------------|
| **EKS** | $73 | $32 | **~$105/month** |
| **GKE** | $0 (first cluster) | $0 (Cloud NAT) | **~$0/month** |
| **AKS** | $0 | $32 | **~$32/month** |

This is before any worker node or load balancer costs.

## Karpenter / node autoscaling equivalent

| Provider | Option | Notes |
|----------|--------|-------|
| **AWS** | Karpenter | GA, mature, AWS-native |
| **GCP** | Node Auto Provisioner (NAP) | GCP's Karpenter equivalent, deeply integrated with GKE |
| **Azure** | AKS Node Autoprovisioning | Based on Karpenter, in preview |

Karpenter's GCP provider exists but is not GA — use NAP on GKE instead.

---

## Load balancer costs and alternatives

Every cloud provider charges a fixed monthly fee per load balancer, plus per-rule and data processing costs.

### Managed load balancers

| Provider | Service name | Fixed cost | Notes |
|----------|-------------|-----------|-------|
| **AWS** | ALB (Application Load Balancer) | ~$18/month + $0.008/LCU | Provisioned per Ingress by the AWS Load Balancer Controller |
| **GCP** | Cloud Load Balancing | ~$18/month + per-rule | Global or regional, HTTPS LB |
| **Azure** | Azure Application Gateway | ~$20/month + per-rule | Or Azure Load Balancer (~$18/month) for L4 |

With the AWS ALB Controller approach (what this repo uses), each Kubernetes `Ingress` resource provisions a separate ALB. One service = one ALB = ~$18/month. This adds up fast with multiple services.

### Self-managed alternatives — classic Ingress API

Run an ingress controller as a pod inside the cluster, with a single load balancer in front. One LB routes all traffic internally — much cheaper for multi-service setups.

> **Note:** NGINX Ingress Controller was deprecated in March 2026. Remaining options:

| Controller | Notes |
|------------|-------|
| **Traefik** | Easy setup, auto-discovers services, built-in dashboard. Has its own proprietary CRD system (`IngressRoute`) which creates vendor lock-in at the config level. Good for simple setups. |
| **HAProxy Ingress** | Niche, less community momentum |
| **Kong Ingress** | Feature-rich API gateway, heavier than a simple ingress controller |

With NGINX deprecated, picking another classic Ingress controller carries the same long-term risk. The Kubernetes project has been pushing Gateway API as the official successor — this is the inflection point to migrate.

### Self-managed alternatives — Gateway API

Gateway API is the official Kubernetes successor to the Ingress API. More expressive, role-oriented, and designed for multi-team multi-service setups.

| Controller | Notes |
|------------|-------|
| **Envoy Gateway** | CNCF project, clean Gateway API implementation, actively developed. Recommended starting point. |
| **Contour** | Mature, Envoy-based, solid Gateway API support |
| **Istio** | Implements Gateway API but brings a full service mesh — significant operational overhead for simple routing |
| **AWS Gateway API Controller** | Integrates with VPC Lattice instead of ALB — AWS-native but very different model |

**Recommendation:** For a new multi-service setup, skip classic Ingress controllers entirely and go straight to Envoy Gateway or Contour with Gateway API. One load balancer in front, all routing handled internally by the controller.
