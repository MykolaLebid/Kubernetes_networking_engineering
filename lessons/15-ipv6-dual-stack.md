# Lesson 15 — IPv6 and Dual-Stack Kubernetes

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 02 — IP Routing](02-ip-routing-and-forwarding.md), [Lesson 09 — CNI](09-cni-specification.md)  
> **Duration:** ~2 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl)
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[*].address}{"\n"}{end}'
kubectl get pods -A -o wide | head -15
kubectl get svc -A | head -10

# Terminal 2 — minikube Linux node
minikube ssh
ip -6 addr show
ip -6 route show
```

---

## Why This Matters

IPv4 exhaustion is real. Cloud providers now charge for public IPv4 addresses, and enterprise networks increasingly mandate IPv6. Kubernetes has had dual-stack support (GA since 1.23) — but configuring it correctly requires understanding how pods, services, and policies work across both address families.

---

## 1. Dual-Stack vs IPv6-Only

**Dual-stack:** Every pod and service has both an IPv4 and IPv6 address. Traffic uses IPv4 or IPv6 based on the caller's preference.

**IPv6-only:** No IPv4 at all — full IPv6. Less common, but increasingly required in some regions and carriers.

```
Dual-Stack Address Assignment

Single-stack (IPv4 only):               Dual-stack (IPv4 + IPv6):

  Node: 192.168.1.10                    Node: 192.168.1.10 / fd00::10
  Pod CIDR: 10.244.1.0/24              Pod CIDR: 10.244.1.0/24 + fd01::/96

  ┌─────────────────────┐               ┌─────────────────────────────────────┐
  │ Pod A               │               │ Pod A                               │
  │ eth0: 10.244.1.5/24 │               │ eth0: 10.244.1.5/24                 │
  │                     │               │       fd01::a:f405/96               │
  └─────────────────────┘               └─────────────────────────────────────┘

  Service (ClusterIP):                  Service (dual-stack ClusterIP):
  10.96.0.10/32                         10.96.0.10/32  (IPv4 ClusterIP)
                                        fd02::a/128    (IPv6 ClusterIP)

ipFamilyPolicy options:
  SingleStack      — one family only (default)
  PreferDualStack  — dual if available, single if not
  RequireDualStack — fail if both not available

NDP (IPv6 Neighbor Discovery) replaces ARP:
  IPv4: Pod → ARP broadcast → "who has 10.244.1.1?"
  IPv6: Pod → ICMPv6 NS    → "who has fd01::1?" (multicast, not broadcast)
```

---

## 2. Enabling Dual-Stack at the Cluster Level

```bash
# kubeadm: enable dual-stack at init
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: "10.244.0.0/16,fd00:10:244::/56"      # IPv4 + IPv6 pod CIDR
  serviceSubnet: "10.96.0.0/12,fd00:10:96::/108"    # IPv4 + IPv6 service CIDR
EOF

kubeadm init --config kubeadm-config.yaml
```

Kubelet flags required:
```
--node-ip=192.168.1.10,fd00::1  # one IPv4, one IPv6 node address
```

---

## 3. Dual-Stack CNI Configuration

### Calico
```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
spec:
  calicoNetwork:
    ipPools:
      - cidr: 10.244.0.0/16
        encapsulation: VXLAN
      - cidr: fd00:10:244::/56
        encapsulation: VXLAN
```

### Cilium
```bash
helm install cilium cilium/cilium \
  --set ipv4.enabled=true \
  --set ipv6.enabled=true \
  --set tunnel=vxlan
```

### Flannel
```json
{
  "Network": "10.244.0.0/16",
  "IPv6Network": "fd00:10:244::/56",
  "EnableIPv6": true,
  "Backend": {"Type": "vxlan"}
}
```

---

## 4. Dual-Stack Services

```yaml
# Prefer IPv6, fall back to IPv4
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  ipFamilyPolicy: PreferDualStack   # or: SingleStack | RequireDualStack
  ipFamilies:
    - IPv6
    - IPv4
  selector:
    app: web
  ports:
    - port: 80
```

```bash
kubectl get svc web
# NAME   TYPE        CLUSTER-IP           CLUSTER-IPS                              PORT(S)
# web    ClusterIP   10.96.42.10          10.96.42.10,fd00:10:96::1               80/TCP
```

ipFamilyPolicy options:
- `SingleStack` — one IP family (default)
- `PreferDualStack` — dual-stack if cluster supports it, else single
- `RequireDualStack` — fail if cluster doesn't support dual-stack

---

## 5. Pod IPv6 Address Assignment

```bash
# Check pod has both addresses
kubectl get pod web-pod -o jsonpath='{.status.podIPs}'
# [{"ip":"10.244.0.6"},{"ip":"fd00:10:244::6"}]

# Inside the pod
kubectl exec -it web-pod -- ip addr
# inet 10.244.0.6/24 brd 10.244.0.255 scope global eth0
# inet6 fd00:10:244::6/64 scope global dynamic

kubectl exec -it web-pod -- ip -6 route
# fd00:10:244::/64 dev eth0 proto kernel scope link src fd00:10:244::6
# default via fd00:10:244::1 dev eth0
```

---

## 6. IPv6 Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-policy-v6
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
    - Ingress
  ingress:
    - from:
        - ipBlock:
            cidr: fd00::/16    # IPv6 CIDR
      ports:
        - port: 80
```

---

## 7. Bare Metal IPv6 Considerations

```bash
# Ensure IPv6 forwarding is enabled on nodes
sysctl net.ipv6.conf.all.forwarding=1
sysctl net.ipv6.conf.eth0.forwarding=1

# Allow iptables to see bridged IPv6 traffic
sysctl net.bridge.bridge-nf-call-ip6tables=1

# Check IPv6 routes
ip -6 route show
ip -6 neigh show   # NDP neighbor table (IPv6 ARP equivalent)

# NDP (Neighbor Discovery Protocol) — IPv6 ARP equivalent
# Check NDP proxy if needed
sysctl net.ipv6.conf.eth0.proxy_ndp=1
```

BGP with IPv6:
```yaml
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: v6-peer
spec:
  peerIP: "fd00::1"           # IPv6 BGP peer
  asNumber: 65000
  sourceAddress: "fd00::10"
```

---

## 8. Cloud Provider Dual-Stack

### AWS EKS
```bash
# Enable IPv6 at cluster creation
aws eks create-cluster \
  --name my-cluster \
  --kubernetes-network-config ipFamily=ipv6

# IPv6 only — pods get IPv6 from VPC subnet
kubectl get node -o jsonpath='{.items[0].status.addresses}'
# Type InternalIP: 2600:1f18:...
```

### GKE
```bash
# Enable dual-stack
gcloud container clusters create my-cluster \
  --enable-ip-alias \
  --stack-type=IPV4_IPV6

kubectl get node -o yaml | grep podCIDRs
# podCIDRs:
# - 10.100.0.0/24
# - fd20::/112
```

### AKS
```bash
# Dual-stack AKS
az aks create \
  --name my-aks \
  --ip-families IPv4 IPv6 \
  --pod-cidr "10.244.0.0/16,fd12:3456:789a::/56" \
  --service-cidr "10.96.0.0/16,fd12:3456:789b::/108"
```

---

## 9. Troubleshooting Dual-Stack

```bash
# 1. Does the node have both addresses?
kubectl get node <node> -o jsonpath='{.status.addresses}'

# 2. Does the pod have both addresses?
kubectl get pod <pod> -o jsonpath='{.status.podIPs}'

# 3. Can pods reach each other over IPv6?
kubectl exec -it pod-a -- ping6 fd00:10:244::7

# 4. Does IPv6 DNS work?
kubectl exec -it pod-a -- nslookup -type=AAAA web.default.svc.cluster.local
# Server: fd00:10:96::a   (kube-dns IPv6 address)

# 5. Check CoreDNS handles IPv6
kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIPs}'

# 6. Verify iptables AND ip6tables rules exist
iptables -t nat -L KUBE-SERVICES -n | grep CLUSTER-IP
ip6tables -t nat -L KUBE-SERVICES -n | grep CLUSTER-IP

# Common issues:
# 1. IPv6 forwarding disabled on nodes
# 2. ip6tables rules not generated by kube-proxy
# 3. CNI doesn't support dual-stack (check plugin docs)
# 4. Cloud VPC doesn't have IPv6 CIDR assigned
# 5. MTU different on IPv6 (requires separate configuration)
```

---

## 10. Summary

| Concept | Detail |
|---------|--------|
| Dual-stack cluster | Requires `--pod-cidr` and `--service-cidr` with both families |
| ipFamilyPolicy | PreferDualStack for gradual migration |
| NDP | IPv6 equivalent of ARP — enabled on each node veth |
| IPv6 forwarding | `net.ipv6.conf.all.forwarding=1` required |
| Cloud support | EKS (IPv6-only), GKE (dual-stack), AKS (dual-stack) |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Killercoda Playground](https://killercoda.com/) | Free | Enable dual-stack on a kind/minikube cluster; inspect IPv6 addresses, test NDP with `ip -6 neigh` |
| [Kubernetes Official Docs: IPv4/IPv6 dual-stack](https://kubernetes.io/docs/concepts/services-networking/dual-stack/) | Free | Official walkthrough with example configs — use alongside the lab commands in this lesson |

---

**Next:** [Lesson 16 — Network Policies: Microsegmentation](16-network-policies.md)
