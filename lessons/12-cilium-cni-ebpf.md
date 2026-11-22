# Lesson 12 — Cilium CNI and eBPF Dataplane

> **Track:** Network Foundation — Bare Metal & Cloud · **Prereqs:** [Lesson 10 — eBPF and XDP](10-ebpf-xdp.md), [Lesson 09 — CNI Specification](09-cni-specification.md) · **Time:** ~3 hours

> **Goal:** Deploy Cilium with kube-proxy replacement, write L7 CiliumNetworkPolicy, and use Hubble to observe and debug live traffic flows.

---

## Practice Setup

```bash
# Terminal 1 — minikube Linux node
minikube ssh
sudo bpftool prog list | grep -i cil | head -10
ip link show | grep -E "cilium|lxc"

# Terminal 2 — Mac (kubectl + cilium CLI)
cilium status 2>/dev/null || echo "cilium CLI not installed: brew install cilium-cli"
kubectl get pods -n kube-system | grep -E "cilium|hubble"
hubble observe --last 10 2>/dev/null || echo "hubble not running"
```

---

## 1. Architecture

```mermaid
flowchart LR
    subgraph CP["Kubernetes Control Plane"]
        API[API Server]
    end
    subgraph OP["cilium-operator\n1-2 replicas"]
        O1[IPAM\nCiliumNode mgmt\nCluster Mesh]
    end
    subgraph Agent["cilium-agent DaemonSet (every node)"]
        BPF[eBPF program loader]
        IDM[Identity management]
        IPAM[IPAM]
        KPR[kube-proxy replacement\neBPF service LB]
        HUB[Hubble server\nflow data export]
    end
    subgraph Envoy["Envoy (L7 policy)"]
        E1[HTTP / gRPC\npolicy enforcement]
    end
    API --> O1
    O1 --> BPF
    BPF --> eBPFmaps[(eBPF Maps\ncilium_lxc\ncilium_policy\ncilium_lb4_services)]
    Agent --> Envoy
    HUB --> HubbleRelay[Hubble Relay\nHubble UI]
```

> **See also:** [Lesson 10 — eBPF and XDP](10-ebpf-xdp.md) for eBPF program types and BPF map internals referenced throughout this lesson.

---

## 2. Identity-Based Policy (vs IP-based)

```mermaid
flowchart LR
    subgraph Traditional["Traditional: IP-based iptables"]
        PA1[Pod A\n10.0.0.5] -->|rule: allow 10.0.0.5/32| PB1[Pod B]
        note1["Problem: IP changes on reschedule"]
    end
    subgraph Cilium["Cilium: Identity-based eBPF"]
        PA2[Pod A\napp=frontend\nidentity: 1234] -->|TC egress stamps id=1234| TC1[TC egress\nBPF prog]
        TC1 -->|VXLAN/Geneve\nencap with identity| TC2[TC ingress\nBPF prog]
        TC2 -->|check id=1234 in policy map| PB2[Pod B\napp=backend]
    end
```

Cilium assigns a **numeric identity** to every pod based on its labels. Policy is enforced per identity, not per IP — policy survives pod restarts.

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

---

## 3. eBPF Hook Points

```mermaid
flowchart TD
    NIC[NIC receive] -->|earliest hook| XDP[XDP\nDDoS / LB offload]
    XDP --> TCI[TC ingress\nbefore routing decision]
    TCI --> Route[Kernel routing]
    Route --> TCE[TC egress\nafter routing, before NIC transmit]
    TCE --> NIC2[NIC transmit]
    Route --> SOCK[Socket layer\nL4 bypass for local traffic]
```

```bash
# View eBPF programs loaded by Cilium
bpftool prog list | grep cilium
cilium bpf prog list

# View eBPF maps (key-value stores shared between kernel and userspace)
cilium bpf map list
# Examples:
#   cilium_lxc          — per-pod identity and endpoint info
#   cilium_policy       — compiled policy rules
#   cilium_ct_tcp4      — connection tracking table
#   cilium_lb4_services — service load balancing table
#   cilium_nat          — NAT table

# View service LB rules in eBPF (kube-proxy replacement)
cilium service list
cilium bpf lb list
```

---

## 4. Installation

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
cilium connectivity test   # end-to-end network tests (~5 min)
```

### Key Helm Parameters

| Parameter | Default | Effect | When to change |
|-----------|---------|--------|----------------|
| `kubeProxyReplacement` | `disabled` | eBPF service LB mode | Set `strict` to fully replace kube-proxy |
| `tunnel` | `vxlan` | Overlay protocol | Set `disabled` for native routing (needs BGP or same L2) |
| `autoDirectNodeRoutes` | `false` | Auto-add routes for same-L2 nodes | Enable with `tunnel=disabled` on bare metal |
| `hubble.relay.enabled` | `false` | Cross-node flow aggregation | Enable for multi-node Hubble visibility |
| `encryption.enabled` | `false` | WireGuard node-to-node encryption | Enable for untrusted networks |
| `loadBalancer.acceleration` | `disabled` | XDP-level service LB | Set `native` on supported NICs for best performance |
| `bpf.masquerade` | `false` | eBPF-based masquerade (replaces iptables MASQ) | Enable when kube-proxy is fully replaced |

---

## 5. Networking Modes

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

## 6. CiliumNetworkPolicy (L3/L4/L7)

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
                path: "/api/.*"    # L7 HTTP rule (Envoy enforces)
  egress:
    - toFQDNs:
        - matchName: "api.example.com"   # FQDN-based policy
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

```yaml
# CiliumClusterwideNetworkPolicy (global, all namespaces)
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

```mermaid
sequenceDiagram
    participant P as Pod / External client
    participant SK as Socket layer\n(BPF sock_ops)
    participant LB as cilium_lb4_services\neBPF map
    participant EP as Backend Pod

    P->>SK: connect to ClusterIP 10.96.0.10:80
    SK->>LB: lookup service → list of backends
    LB-->>SK: backend: 10.244.1.5:8080 (hash-selected)
    SK->>EP: direct socket to backend (no DNAT overhead)
    EP-->>P: response via conntrack
```

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

Hubble provides real-time flow visibility at the kernel level using eBPF ring buffers.

```bash
# Enable port-forward to Hubble relay
cilium hubble port-forward &

# Observe all flows in the cluster
hubble observe

# Filter by pod pair
hubble observe --from-pod default/frontend --to-pod default/backend

# Filter by policy verdict (dropped packets)
hubble observe --verdict DROPPED

# Filter by HTTP status
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

## 10. Cilium on Cloud Providers

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

## Troubleshooting

| Symptom | Likely Cause | Diagnostic Command | Fix |
|---------|-------------|-------------------|-----|
| `cilium status` shows agents not ready | Kernel version <4.9 or missing BPF filesystem | `cilium version; uname -r` | Upgrade kernel to 5.4+; mount bpffs: `mount bpffs /sys/fs/bpf -t bpf` |
| Policy not enforced — traffic passes that should be dropped | Policy not compiled or identity mismatch | `cilium policy trace --src-pod ns/pod-a --dst-pod ns/pod-b --dport 80` | Check endpoint selector label matches; re-apply policy |
| Services not reachable after enabling kube-proxy replacement | kube-proxy still running and conflicting | `cilium status \| grep KubeProxyReplacement` | Remove kube-proxy DaemonSet; ensure `kubeProxyReplacement=strict` |
| `hubble observe` shows no flows | Hubble relay not enabled | `cilium status \| grep Hubble` | Upgrade Cilium with `hubble.relay.enabled=true` |
| Intermittent connection drops between pods | conntrack table exhausted | `cilium metrics \| grep drop; cilium bpf ct list global \| wc -l` | Increase `bpf-ct-global-tcp-max` in Helm values |
| L7 HTTP policy not blocking requests | Envoy sidecar not injected | `kubectl logs cilium-pod -c cilium-envoy` | Check Envoy port 9090 is listening; verify CiliumNetworkPolicy has `http` rules |
| XDP acceleration not working | NIC driver not XDP-compatible | `cilium status \| grep XDP` | Use `loadBalancer.acceleration=disabled` or upgrade NIC drivers |

---

## Production Checklist

- [ ] Run `cilium connectivity test` after every Cilium upgrade before returning to production
- [ ] Set `kubeProxyReplacement=strict` and remove kube-proxy DaemonSet when enabling eBPF service LB
- [ ] Enable Hubble relay (`hubble.relay.enabled=true`) so flows are visible across all nodes
- [ ] Size the eBPF CT table for expected connection count (`bpf-ct-global-tcp-max`: default 512Ki)
- [ ] Tune `bpf.masquerade=true` to move masquerade off iptables once kube-proxy is replaced
- [ ] Deploy Tetragon alongside Cilium for runtime security audit of syscalls and file access
- [ ] Use `CiliumClusterwideNetworkPolicy` default-deny with `fromEntities: cluster` before cluster goes to production

---

## Common Anti-Patterns

| What people do | Why it breaks | Correct approach |
|---------------|--------------|-----------------|
| Run kube-proxy alongside `kubeProxyReplacement=strict` | Both programs service VIPs; iptables rules conflict with eBPF maps causing intermittent drops | Remove kube-proxy DaemonSet completely when using strict replacement |
| Write standard `NetworkPolicy` and `CiliumNetworkPolicy` for the same pods | Both apply additively; unexpected intersections can over-restrict or leave gaps | Migrate entirely to `CiliumNetworkPolicy`; use standard only when CNI portability is needed |
| Use FQDN policy without DNS proxy enabled | FQDN rules require Cilium's DNS proxy to intercept responses; without it rules never fire | Ensure `--enable-dns-proxy=true` (default); verify with `cilium config view \| grep dns-proxy` |
| Enable cluster mesh without unique cluster names/IDs | Identity collisions across clusters cause policy bypasses | Set unique `cluster.name` and `cluster.id` in Helm values before connecting clusters |
| Leave `hubble.retention` at default on high-traffic cluster | Hubble ring buffer fills; oldest flows are dropped before they can be inspected | Tune `hubble.eventBufferCapacity` based on cluster throughput |

---

## Quick Reference

| Use Case | Command |
|---------|---------|
| Overall Cilium health | `cilium status` |
| Run connectivity tests | `cilium connectivity test` |
| List pod endpoints with identities | `cilium endpoint list` |
| Trace policy between two pods | `cilium policy trace --src-pod ns/pod-a --dst-pod ns/pod-b --dport 80` |
| Observe live flows | `hubble observe` |
| Observe dropped flows only | `hubble observe --verdict DROPPED` |
| List eBPF service LB rules | `cilium service list` |
| List eBPF backend map | `cilium bpf lb list` |
| List loaded eBPF programs | `bpftool prog list \| grep cilium` |
| Check WireGuard encryption status | `cilium encrypt status` |
| Get endpoint details | `cilium endpoint get <endpoint-id>` |
| View identity for a label set | `cilium identity list` |

---

## Summary

| Feature | Cilium Mechanism |
|---------|-----------------|
| Pod networking | eBPF programs at TC hook on each veth |
| kube-proxy replacement | eBPF service map + socket-level LB |
| NetworkPolicy | Identity-based eBPF programs (no IP dependency) |
| L7 policy (HTTP/gRPC) | Envoy sidecar managed by Cilium agent |
| Observability | Hubble (eBPF ring buffers → Hubble relay → UI) |
| Encryption | WireGuard or IPsec transparent node-to-node |
| Multi-cluster | Cilium Cluster Mesh (shared service discovery) |
| Runtime security | Tetragon (syscall-level eBPF audit) |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Isovalent: Getting Started with Cilium](https://isovalent.com/labs/getting-started-with-cilium/) | Free | Install Cilium, use Hubble for traffic inspection, enable encryption — covers this entire lesson |
| [Isovalent: Foundations — Kubernetes Networking and Cilium](https://isovalent.com/labs/getting-started-with-kubernetes-networking-and-cilium/) | Free | Pod networking, CNI, IPAM, services, ingress, and network policies all with Cilium |
| [Killercoda Playground](https://killercoda.com/) | Free | Run `cilium status`, `hubble observe`, inspect BPF maps with `bpftool` on a real cluster |

---

**Next:** [Lesson 13 — Kubernetes Services and kube-proxy](13-kubernetes-services-kube-proxy.md)
