# Kubernetes & Tool Version Matrix

Minimum versions required for features covered in each lesson.

---

## Kubernetes Version Requirements

| Feature | Min K8s Version | Lesson | Notes |
|---------|----------------|--------|-------|
| EndpointSlices (GA) | 1.21 | 13 | Replaces Endpoints at scale |
| Dual-stack (GA) | 1.23 | 15 | Both IPv4 + IPv6 pod/service CIDRs |
| Gateway API (beta) | 1.24 | 18 | Requires separate Gateway API CRDs install |
| Gateway API (GA) | 1.28 | 18 | GatewayClass, HTTPRoute stable |
| Gateway API v1.3 (request mirroring, CORS, retry budgets) | 1.30 | 18 | GatewayClass merging, Inference Extension |
| kube-proxy nftables mode (alpha) | 1.29 | 13 | `--proxy-mode=nftables`; kernel 5.13+ |
| kube-proxy nftables mode (beta) | 1.33 | 13 | IPVS deprecation announced Nov 2026 |
| NetworkPolicy (GA) | 1.7 | 16 | Requires CNI enforcement (not built-in) |
| PodDisruptionBudget | 1.21 | 17 | For ingress controller HA |
| IPVS kube-proxy mode | 1.11 | 13 | Requires kernel ipvs modules |
| NodeLocal DNSCache | 1.18 | 14 | DaemonSet on 169.254.20.10 |
| TopologyAwareHints | 1.23 | 13 | Successor to service topology |
| Security Groups for Pods (EKS) | 1.17 | 29 | Requires VPC CNI 1.7.7+ |
| Prefix Delegation (EKS) | 1.21 | 29 | Requires VPC CNI 1.9.0+ |
| EKS Managed Node Groups | 1.14 | 29 | |
| ArgoCD ApplicationSet | 2.0 | 33 | Cluster + git generators |
| ArgoCD Sync Waves | 1.8 | 33 | Via annotation |

---

## CNI Plugin Version Requirements

| Plugin | Min Version | Feature | Lesson |
|--------|-------------|---------|--------|
| Calico | 3.21 | eBPF dataplane (GA) | 11 |
| Calico | 3.14 | WireGuard node-to-node encryption | 11 |
| Calico | 3.11 | IPAM block size tuning | 11 |
| Calico | 3.33 | Current stable (Nov 2026) | 11 |
| Cilium | 1.15 | Hubble OTLP export | 24, 40 |
| Cilium | 1.20 | Current stable (1.20.5, Nov 2026); remote node workload info in Hubble flows | 12, 24, 40 |
| Cilium | 1.11 | Cluster Mesh (stable) | 22 |
| Cilium | 1.10 | kube-proxy replacement (GA) | 12 |
| Cilium | 1.9 | WireGuard node-to-node encryption | 23 |
| Cilium | 1.8 | Hubble (GA) | 24 |
| Cilium | 1.7 | FQDN-based egress policy | 16, 23 |
| MetalLB | 0.16 | Current stable (0.16.2, Nov 2026) | 19 |
| MetalLB | 0.13 | CRD-based config (IPAddressPool) | 19 |
| MetalLB | 0.11 | BGP with BFD | 19 |

---

## Istio Version Requirements

| Feature | Min Istio Version | Lesson |
|---------|------------------|--------|
| Ambient mode (beta) | 1.18 | 21 |
| Ambient mode (GA) | 1.24 | 21 |
| Gateway API support | 1.16 | 21 |
| Telemetry API | 1.12 | 21 |
| ProxyConfig API | 1.12 | 21 |
| External Authorization | 1.9 | 21 |
| Current stable | 1.32 (Nov 2026) | 21 |

---

## AWS / EKS Version Requirements

| Feature | Min Version | Lesson |
|---------|-------------|--------|
| VPC CNI prefix delegation | VPC CNI 1.9.0 / K8s 1.21 | 29 |
| Security Groups for Pods | VPC CNI 1.7.7 / K8s 1.17 | 29 |
| AWS LBC NLB (target type ip) | LBC 2.0.0 | 31 |
| AWS LBC ALB IngressGroup | LBC 1.1.0 | 31 |
| EKS Managed Addons | EKS 1.18 | 29 |
| EKS Pod Identity | EKS 1.24 | 29 |
| VPC Lattice | EKS 1.26 | 32 |

---

## OpenShift Version Requirements

| Feature | Min OCP Version | Lesson |
|---------|----------------|--------|
| OVN-Kubernetes default CNI | OCP 4.6 | 26 |
| Hybrid Overlay (Windows nodes) | OCP 4.6 | 26 |
| EgressIP HA (OVN-K) | OCP 4.9 | 28 |
| EgressFirewall DNS rules | OCP 4.7 | 28 |
| HAProxy Router sharding | OCP 4.1 | 27 |
| IngressController operator | OCP 4.1 | 27 |

---

## eBPF / Kernel Requirements

| Feature | Min Linux Kernel | Lesson |
|---------|----------------|--------|
| XDP (native mode) | 4.8 | 10 |
| XDP (generic mode) | 4.12 | 10 |
| TC eBPF programs | 4.1 | 10 |
| BPF ring buffer | 5.8 | 10 |
| eBPF CO-RE (portable) | 5.2 | 10 |
| BPF LSM hooks | 5.7 | 10, 23 |
| Cilium eBPF kube-proxy | 4.19 (5.10 recommended) | 12 |
| Tetragon | 5.4 | 10, 23 |
| WireGuard (kernel built-in) | 5.6 | 23 |

---

## OpenTelemetry Version Requirements

| Component | Min Version | Feature | Lesson |
|-----------|-------------|---------|--------|
| OTel Collector | 0.100+ | OTTL v1 stable (transform/filter processors) | 40 |
| OBI (formerly Beyla) | 1.0 | GA — HTTP/gRPC/SQL/Redis/Kafka/MongoDB/GraphQL/Elasticsearch/S3; kernel 4.18+ | 40 |
| K8s OTel Operator | 0.95+ | Instrumentation CRD for Python/Java/Node/Go/.NET/NGINX | 40 |
| Cilium | 1.15 | Hubble OTLP export | 24, 40 |
| nftables kernel | 5.13 | kube-proxy nftables mode | 13 |

---

## minikube / Lab Environment

| Requirement | Version / Notes | Lesson |
|-------------|----------------|--------|
| minikube | ≥ 1.28 | All |
| kubectl | matches cluster | All |
| bpftool | kernel 5.x+ | 10 |
| calicoctl | matches Calico version | 11 |
| cilium CLI | ≥ 0.15 | 12 |
| istioctl | ≥ 1.24 (for ambient GA) | 21 |
| argocd CLI | ≥ 3.0 | 33 |
| Podman / Docker | for minikube driver | All |
