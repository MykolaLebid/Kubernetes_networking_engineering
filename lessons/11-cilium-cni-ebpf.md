# Lesson 11 — Cilium CNI and eBPF Dataplane

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 09 — CNI Specification](09-cni-specification.md), [Lesson 03 — iptables](03-iptables-and-netfilter.md)  
> **Duration:** ~3 hours

---

## Why This Matters

Cilium is the most technically advanced Kubernetes CNI, using eBPF to replace iptables and kube-proxy. It powers GKE Dataplane v2, EKS Anywhere, and many performance-critical environments. Its observability tool (Hubble) provides flow-level visibility that is impossible with traditional tools.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│  Kubernetes Control Plane                           │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  cilium-operator (1-2 replicas)                     │
│  IPAM, CiliumNode management, cluster-mesh          │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  cilium-agent (DaemonSet on every node)             │
│  ├── eBPF program loader                            │
│  ├── Identity management                            │
│  ├── IPAM (allocate pod IPs)                        │
│  ├── kube-proxy replacement (eBPF service LB)       │
│  └── Hubble server (flow data export)               │
└─────────────────────────────────────────────────────┘
```

---

## 2. eBPF Fundamentals

eBPF (extended Berkeley Packet Filter) allows attaching custom programs to kernel hook points without kernel module development.

```
Hook points used by Cilium:

XDP        — earliest hook, on NIC receive path (DDoS, LB offload)
TC ingress — after skb allocation, before routing
TC egress  — after routing decision, before NIC transmit
Socket     — L4 socket layer (bypass network stack for local traffic)
```

```bash
# View eBPF programs loaded by Cilium
bpftool prog list | grep cilium
# or:
cilium bpf prog list

# View eBPF maps (key-value stores shared between kernel and userspace)
cilium bpf map list
# Examples:
# cilium_lxc          — per-pod identity and endpoint info
# cilium_policy       — compiled policy rules
# cilium_ct_tcp4      — connection tracking table
# cilium_lb4_services — service load balancing table
# cilium_nat          — NAT table

# View service LB rules in eBPF (kube-proxy replacement)
cilium service list
cilium bpf lb list
```

---

## 3. Installation

```bash
# Install Cilium with Helm
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=strict \
  --set k8sServiceHost=<API_SERVER_IP> \
  --set k8sServicePort=6443 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

# Verify installation
cilium status --wait
cilium connectivity test   # end-to-end network tests (takes ~5 min)
```

---

## 4. Networking Modes

### Tunnel (default — works everywhere)
```bash
# VXLAN tunnel (default)
cilium config view | grep tunnel
# tunnel-protocol: vxlan

# Switch to Geneve
helm upgrade cilium cilium/cilium --reuse-values \
  --set tunnel=geneve
```

### Native Routing (bare metal, cloud with routing support)
```bash
helm upgrade cilium cilium/cilium --reuse-values \
  --set tunnel=disabled \
  --set autoDirectNodeRoutes=true \
  --set ipv4NativeRoutingCIDR=10.244.0.0/16
```

### WireGuard Transparent Encryption
```bash
helm upgrade cilium cilium/cilium --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard

cilium encrypt status
```

---

## 5. Identity-Based Security

Cilium assigns a **numeric identity** to every pod based on its labels. Policy is enforced per identity, not per IP.

```bash
# View endpoint identities
cilium endpoint list
# ENDPOINT  POLICY (ingress)  POLICY (egress)  IDENTITY  LABELS
# 1234      Enabled           Enabled          12345     app=web,env=prod

# View all identities in the cluster
cilium identity list

# What is identity 12345?
cilium identity get 12345
```

This means policy survives pod restarts (IPs change, labels don't).

---

## 6. CiliumNetworkPolicy

```yaml
# More expressive than standard NetworkPolicy
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: web-policy
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: web
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
          rules:
            http:
              - method: "GET"
                path: "/api/.*"    # L7 HTTP rule
  egress:
    - toFQDNs:
        - matchName: "api.example.com"   # FQDN-based policy
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

```yaml
# CiliumClusterwideNetworkPolicy (global)
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-deny
spec:
  endpointSelector: {}   # all pods
  ingress:
    - fromEntities:
        - cluster         # allow intra-cluster
  egress:
    - toEntities:
        - cluster
    - toFQDNs:
        - matchPattern: "*.amazonaws.com"
```

---

## 7. kube-proxy Replacement

Cilium implements Service load-balancing entirely in eBPF — no iptables, no kube-proxy process needed.

```bash
# Check if kube-proxy replacement is active
cilium status | grep KubeProxyReplacement
# KubeProxyReplacement: Strict

# View services handled by eBPF LB
cilium service list
# ID   Frontend               Service Type   Backend
# 1    10.96.0.1:443/TCP      ClusterIP      192.168.1.10:6443/TCP

# View backend set for a service
cilium bpf lb list | grep 10.96.0.1

# View NAT table (replaces conntrack for intra-cluster traffic)
cilium bpf nat list
```

---

## 8. Hubble — eBPF-Powered Observability

Hubble provides real-time flow visibility at the kernel level.

```bash
# Install Hubble CLI
# https://github.com/cilium/hubble/releases

# Enable port-forward to Hubble relay
cilium hubble port-forward &

# Observe all flows in the cluster
hubble observe

# Filter by pod
hubble observe --from-pod default/frontend --to-pod default/backend

# Filter by policy verdict (dropped packets)
hubble observe --verdict DROPPED

# Filter by HTTP
hubble observe --protocol http --http-status 500

# Output as JSON for processing
hubble observe -o json | jq '.flow | {src: .source.pod_name, dst: .destination.pod_name, verdict: .verdict}'

# Open Hubble UI
cilium hubble ui
```

---

## 9. Cluster Mesh

Connect multiple Kubernetes clusters so pods can communicate cross-cluster.

```bash
# Enable cluster mesh on cluster A
cilium clustermesh enable --service-type LoadBalancer
cilium clustermesh status

# Connect cluster A to cluster B
cilium clustermesh connect --context cluster-b

# Share a service across clusters
kubectl annotate svc my-service \
  service.cilium.io/global=true \
  service.cilium.io/shared=true
```

---

## 10. Troubleshooting Cilium

```bash
# Overall status
cilium status
cilium connectivity test

# Check specific pod connectivity
cilium endpoint get <endpoint-id>
cilium policy trace \
  --src-pod default/frontend \
  --dst-pod default/backend \
  --dport 80

# Is a packet being dropped?
hubble observe --verdict DROPPED --last 100

# Check eBPF program tail drops
cilium metrics | grep drop

# Debug mode for a single endpoint
cilium endpoint config <id> Debug=true
kubectl logs -n kube-system cilium-xxxxx | grep -E "WARN|ERROR"

# Check kernel compatibility
cilium version
# System BPF map size is at the limit
# → increase ulimits or use newer kernel

# Common issues:
# 1. Kernel too old (need 4.9+ for basic, 5.4+ for all features)
# 2. conntrack table too small
# 3. Missing BPF filesystem mount: mount bpffs /sys/fs/bpf -t bpf
# 4. Policy stuck in "Waiting" — check cilium-operator logs
```

---

## 11. Cilium on Cloud Providers

```bash
# EKS — Cilium as CNI (replace aws-vpc-cni)
eksctl create cluster --config-file - <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: cilium-cluster
  region: us-east-1
addons:
  - name: vpc-cni
    # don't install — Cilium replaces it
EOF

# GKE — Dataplane v2 uses Cilium automatically
gcloud container clusters create ... \
  --dataplane-v2

# AKS — Cilium option
az aks create \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --network-dataplane cilium
```

---

## 12. Summary

| Feature | Cilium Mechanism |
|---------|-----------------|
| Pod networking | eBPF programs at TC hook |
| kube-proxy replacement | eBPF service map + socket-level LB |
| NetworkPolicy | Identity-based eBPF programs |
| L7 policy (HTTP/gRPC) | Envoy sidecar managed by Cilium |
| Observability | Hubble (eBPF ring buffers) |
| Encryption | WireGuard or IPsec transparent |
| Multi-cluster | Cilium Cluster Mesh |

---

**Next:** [Lesson 12 — Kubernetes Services and kube-proxy](12-kubernetes-services-kube-proxy.md)
