# Lesson 11 — Calico CNI Deep Dive

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 06 — BGP](06-bgp-fundamentals.md), [Lesson 09 — CNI Specification](09-cni-specification.md)  
> **Duration:** ~3 hours

---

## Practice Setup

```bash
# Terminal 1 — minikube Linux node
minikube ssh
sudo calicoctl node status 2>/dev/null || echo "calicoctl not in PATH, try: kubectl exec -n calico-system ..."
ip route show | grep -E "cali|bird|blackhole"
ip link show | grep cali

# Terminal 2 — Mac (kubectl + calicoctl)
kubectl get pods -n calico-system
kubectl get felixconfiguration default -o yaml 2>/dev/null
kubectl get ipamblocks 2>/dev/null | head -10
```

---

## Why This Matters

Calico is the most widely deployed CNI plugin for production Kubernetes. It supports both overlay and native routing modes, implements the full Kubernetes NetworkPolicy API, and offers an eBPF dataplane as an alternative to kube-proxy. Understanding Calico deeply pays dividends in almost any production environment.

---

## 1. Calico Architecture

```
┌──────────────────────────────────────────┐
│  Kubernetes Control Plane                │
│  (APIServer, etcd)                       │
└────────────────┬─────────────────────────┘
                 │  CRDs (IPPool, NetworkPolicy, BGPPeer...)
┌────────────────▼─────────────────────────┐
│  calico-kube-controllers                 │
│  (watches K8s objects → updates Calico)  │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│  calico-node (DaemonSet on every node)   │
│  ├── Felix (enforces policy, programs    │
│  │          iptables/eBPF/routes)        │
│  ├── BIRD (BGP agent, advertises routes) │
│  └── confd (renders BIRD config)         │
└──────────────────────────────────────────┘
```

---

## 2. Installation

```bash
# Install Calico via Tigera Operator (recommended)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
        cidr: 10.244.0.0/16
        encapsulation: VXLANCrossSubnet  # or None, IPIP, VXLAN
        natOutgoing: Enabled
        nodeSelector: all()
EOF
```

---

## 3. Data Plane Modes

### Native Routing (BGP, no overlay)
Best performance. Requires L2 adjacency or BGP-capable switches.
```yaml
spec:
  calicoNetwork:
    ipPools:
      - encapsulation: None      # no overlay
        bgp: Enabled
```

### IPIP (IP-in-IP)
Encapsulates IP packets inside IP packets. Lower overhead than VXLAN (20 bytes vs 50).
```yaml
encapsulation: IPIP               # all traffic
# or:
encapsulation: IPIPCrossSubnet    # only cross-subnet traffic (native within subnet)
```

### VXLAN
UDP encapsulation. Works where IPIP is blocked (some cloud environments).
```yaml
encapsulation: VXLAN
encapsulation: VXLANCrossSubnet
```

### eBPF Dataplane
Replaces kube-proxy and iptables with eBPF programs.
```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
spec:
  calicoNetwork:
    linuxDataplane: BPF
```

---

## 4. Felix — The Policy Engine

Felix is the per-node agent that programs the dataplane.

```bash
# Check Felix status
kubectl exec -n calico-system calico-node-xxxxx -- calico-node -felix-live
kubectl logs -n calico-system calico-node-xxxxx -c calico-node | grep felix

# Felix diagnostic snapshot
kubectl exec -n calico-system calico-node-xxxxx -- calico-node -diags

# Felix configuration
kubectl get felixconfigurations default -o yaml
```

Key Felix responsibilities:
- Programs iptables/nftables/eBPF rules for NetworkPolicy
- Sets up routing for each local pod
- Manages `cali*` veth interfaces
- Programs iptables rules for NAT (masquerade)

---

## 5. Pod Interface Naming

```bash
# Each pod gets a veth pair:
# Host side: cali<hash>  (e.g., cali9abc1234)
# Pod side:  eth0

# View all Calico interfaces on a node
ip link show | grep cali

# Calico uses proxy ARP on the host veth so pods can use a /32 address
cat /proc/sys/net/ipv4/conf/cali9abc1234/proxy_arp
# 1

# Each pod gets a /32 host route on the node
ip route show | grep cali
# 10.244.0.6 dev cali9abc1234 scope link
```

---

## 6. IP Pools and IPAM

```bash
# View IP pools
calicoctl get ippool -o wide
kubectl get ippool -o yaml   # via CRD

# View IPAM blocks (how the pool is divided per node)
calicoctl ipam show --show-blocks
# +----------+-------------------+----------+----------+
# | GROUPING |       CIDR        | IPS USED | IPS FREE |
# +----------+-------------------+----------+----------+
# | IP Pool  | 10.244.0.0/16    |       48 |    65488 |
# | Block    | 10.244.0.0/26    |       16 |       48 |

# Which pod owns which IP
calicoctl ipam show --ip 10.244.0.6

# Release a leaked IP (after pod deletion)
calicoctl ipam release --ip=10.244.0.6
```

---

## 7. NetworkPolicy with Calico

Calico implements Kubernetes NetworkPolicy and also provides its own richer CRDs.

### Kubernetes NetworkPolicy
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-ingress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: frontend
      ports:
        - protocol: TCP
          port: 80
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53   # allow DNS
```

### Calico GlobalNetworkPolicy (cluster-wide)
```yaml
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: default-deny-all
spec:
  selector: all()
  types:
    - Ingress
    - Egress
  egress:
    - action: Allow
      protocol: UDP
      destination:
        ports: [53]        # DNS always allowed
```

### Calico NetworkSet (IP ranges in policy)
```yaml
apiVersion: projectcalico.org/v3
kind: GlobalNetworkSet
metadata:
  name: trusted-cidr
  labels:
    env: trusted
spec:
  nets:
    - 10.100.0.0/16
    - 192.168.50.0/24
---
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: allow-trusted
spec:
  selector: all()
  ingress:
    - action: Allow
      source:
        selector: env == "trusted"
```

---

## 8. BGP Configuration

```bash
# View BGP status
calicoctl node status

# BGP peers
kubectl get bgppeers -o yaml

# BGP configuration
kubectl get bgpconfigurations default -o yaml

# Configure full mesh (default)
kubectl apply -f - <<EOF
apiVersion: projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  nodeToNodeMeshEnabled: true
  asNumber: 64512
EOF

# Configure Route Reflector
kubectl annotate node rr-node-01 \
  projectcalico.org/RouteReflectorClusterID=244.0.0.1

kubectl apply -f - <<EOF
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: peer-with-rr
spec:
  nodeSelector: "!has(projectcalico.org/RouteReflectorClusterID)"
  peerSelector: "has(projectcalico.org/RouteReflectorClusterID)"
EOF
```

---

## 9. Troubleshooting Calico

```bash
# Overall health
calicoctl node status
kubectl get tigerastatus

# Is Felix in sync?
kubectl logs -n calico-system calico-node-xxxxx -c calico-node | grep -E "Sync|ERROR|WARN"

# Check iptables rules programmed by Felix
iptables -t filter -L cali-FORWARD -n -v
iptables -t nat -L cali-nat-outgoing -n -v

# Check routing table for pod routes
ip route show | grep cali

# Test policy enforcement
# (run this from a pod and check if connection is allowed/denied)
kubectl exec -it test-pod -- curl -v http://10.244.0.6:80

# View Calico's understanding of a pod's policy
calicoctl get workloadendpoint -n default <pod-name> -o yaml

# Check BIRD routing tables
kubectl exec -n calico-system calico-node-xxxxx -- birdcl show protocols
kubectl exec -n calico-system calico-node-xxxxx -- birdcl show route

# Felix log level (temporarily increase)
kubectl patch felixconfiguration default --type merge \
  -p '{"spec":{"logSeverityScreen":"Debug"}}'
```

---

## 10. Calico on Cloud Providers

### AWS EKS
```bash
# Install Calico for policy only (use AWS VPC CNI for networking)
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml
```

### GKE
```bash
# Calico NetworkPolicy on GKE requires enabling at cluster creation
gcloud container clusters create ... --network-policy
```

### AKS
```bash
# Enable Calico NetworkPolicy on AKS
az aks create --network-policy calico --network-plugin azure ...
```

---

## 11. Summary

| Component | Role |
|-----------|------|
| Felix | Per-node agent: programs routes, iptables/eBPF, NetworkPolicy |
| BIRD | BGP daemon: advertises pod routes to peers |
| calico-ipam | IP address management with per-node IPAM blocks |
| Tigera Operator | Installs and manages Calico components |
| GlobalNetworkPolicy | Cluster-wide policy (richer than K8s NetworkPolicy) |
| eBPF dataplane | Replaces kube-proxy; better performance |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Killercoda Playground](https://killercoda.com/) | Free | Instant Kubernetes cluster with Calico; run `calicoctl node status`, `ip route show proto bird`, inspect `cali*` interfaces |
| [Isovalent: Foundations — Kubernetes Networking and Cilium](https://isovalent.com/labs/getting-started-with-kubernetes-networking-and-cilium/) | Free | Covers IPAM, CNI concepts, and pod networking — directly applicable to understanding Calico IPAM blocks |
| [Project Calico — Interactive Demos](https://www.tigera.io/learn/guides/kubernetes-networking/) | Free | Official Calico/Tigera learning resources including BGP and policy guides |

---

**Next:** [Lesson 12 — Cilium CNI and eBPF Dataplane](12-cilium-cni-ebpf.md)
