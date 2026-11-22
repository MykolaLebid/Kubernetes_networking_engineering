# Lesson 17 — Load Balancing on Bare Metal: MetalLB and kube-vip

> **Track:** Network Foundation — Bare Metal  
> **Prerequisites:** [Lesson 06 — BGP](06-bgp-fundamentals.md), [Lesson 12 — Services](13-kubernetes-services-kube-proxy.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl)
kubectl get pods -n metallb-system 2>/dev/null || echo "MetalLB not installed"
kubectl get ipaddresspools,l2advertisements -n metallb-system 2>/dev/null
kubectl get svc -A --field-selector spec.type=LoadBalancer

# Terminal 2 — minikube Linux node (inspect ARP for L2 mode)
minikube ssh
arp -n | head -20
ip neigh show
```

---

## Why This Matters

Cloud Kubernetes clusters get a load balancer automatically when you create a `type: LoadBalancer` service. On bare metal, that request stays pending forever — `EXTERNAL-IP: <pending>` — until you deploy MetalLB or kube-vip. These tools bring cloud-like LoadBalancer provisioning to on-premises and bare-metal clusters.

---

## 1. The Bare Metal LB Problem

```bash
# Without a LB controller, LoadBalancer services hang:
kubectl get svc web
# NAME   TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
# web    LoadBalancer   10.96.42.10   <pending>     80:30080/TCP   10m
```

The Cloud Controller Manager (CCM) provisions cloud LBs. On bare metal, you need to run your own LB controller.

---

## 2. MetalLB Overview

MetalLB implements LoadBalancer by either:
- **L2 mode**: answers ARP/NDP for the VIP on the local subnet
- **BGP mode**: advertises VIP routes to upstream routers

```bash
# Install MetalLB
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace

kubectl get pods -n metallb-system
# metallb-controller-xxx  (allocates IPs)
# metallb-speaker-xxx     (announces IPs — DaemonSet)
```

---

## 3. MetalLB L2 Mode

The speaker pod on the node holding the VIP responds to ARP requests for that IP.

```yaml
# Configure an IP address pool
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.100.100-192.168.100.200
    - 192.168.200.0/24
---
# Enable L2 advertisement
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - production-pool
  nodeSelectors:               # optional: which nodes can announce
    - matchLabels:
        node-role.kubernetes.io/worker: ""
```

**L2 mode limitations:**
- Single node holds the VIP at a time (failover on node failure, ~10s)
- All traffic enters through one node (no true load balancing at the LB layer)
- Works only within the same L2 broadcast domain

---

## 4. MetalLB BGP Mode

Announces VIPs via BGP to upstream routers. Multiple nodes can announce the same VIP via ECMP.

```yaml
# BGP Peer (ToR switch)
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: tor-switch
  namespace: metallb-system
spec:
  myASN: 64512
  peerASN: 65000
  peerAddress: 192.168.1.1
  holdTime: 30s
  keepaliveTime: 10s
---
# Advertise pool via BGP
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - production-pool
  communities:
    - 64512:100       # tag with community for upstream policy
  aggregationLength: 32   # advertise host routes (/32)
```

**BGP mode advantages:**
- ECMP: multiple nodes announce same VIP → load balancing at router level
- Fast failover (BFD sub-second)
- Works across L3 boundaries (across routers, not just L2)

---

## 5. Using the LoadBalancer Service

```yaml
# Assign from a specific pool
apiVersion: v1
kind: Service
metadata:
  name: web
  annotations:
    metallb.io/address-pool: production-pool
    metallb.io/loadBalancerIPs: 192.168.100.105  # request specific IP
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 8080
```

```bash
kubectl get svc web
# NAME   TYPE           CLUSTER-IP    EXTERNAL-IP       PORT(S)   AGE
# web    LoadBalancer   10.96.42.10   192.168.100.105   80/TCP    30s
```

---

## 6. kube-vip

kube-vip provides VIP management using VRRP (ARP-based HA) or BGP. Also handles HA for the Kubernetes control plane API server.

```bash
# Install kube-vip as a DaemonSet for LoadBalancer services
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml

# Generate kube-vip DaemonSet manifest
docker run --network host --rm \
  ghcr.io/kube-vip/kube-vip:latest \
  manifest daemonset \
  --services \
  --arp \
  --leaderElection \
  | kubectl apply -f -
```

```yaml
# kube-vip ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-vip
  namespace: kube-system
data:
  range-global: "192.168.100.100-192.168.100.200"
```

**kube-vip vs MetalLB:**
- kube-vip: also handles control-plane VIP (HA API server), simpler setup
- MetalLB: more mature, BGP ECMP, richer IP pool management

---

## 7. Shared IPs Across Services

Both tools support multiple services sharing one IP (different ports).

```yaml
# MetalLB shared IP
metadata:
  annotations:
    metallb.io/allow-shared-ip: "web-group"   # same key = shared IP
---
# Service 1: port 80
# Service 2: port 443
# Both get the same EXTERNAL-IP
```

---

## 8. Troubleshooting

```bash
# MetalLB: Is the speaker announcing the IP?
kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker | \
  grep -E "announcing|withdraw|ERROR"

# Check which node is the speaker for a VIP
kubectl get events -n metallb-system | grep announcing

# Is the VIP reachable at L2?
arping -I eth0 192.168.100.105  # from outside the cluster

# Is the VIP route in BGP (BGP mode)?
# On ToR switch:
# show bgp ipv4 unicast 192.168.100.105

# Check IP pool allocation
kubectl get ipaddresspool -n metallb-system
kubectl describe ipaddresspool production-pool -n metallb-system

# kube-vip: check leader election
kubectl logs -n kube-system -l app=kube-vip | grep -E "leader|VIP|ERROR"

# Common issues:
# 1. VIP in same subnet as nodes? (L2 mode requirement)
# 2. ARP blocked by switch (port security)
# 3. BGP session not established (firewall on TCP 179)
# 4. IP pool exhausted
# 5. Node firewall blocking traffic on the VIP port
```

---

## 9. Production Considerations

```bash
# Separate the LB VIP range from node IPs to avoid conflicts
# Node subnet:  192.168.1.0/24
# VIP pool:     192.168.100.0/24  (different subnet, routed via ToR)

# Use BGP mode for production — no single point of failure
# Use L2 mode for dev/lab — simpler, no BGP required

# MetalLB BGP with BFD for fast failover
apiVersion: metallb.io/v1beta2
kind: BGPPeer
spec:
  bfdProfile: fast-bfd
---
apiVersion: metallb.io/v1beta1
kind: BFDProfile
metadata:
  name: fast-bfd
spec:
  receiveInterval: 300    # 300ms
  transmitInterval: 300
  detectMultiplier: 3     # 3 × 300ms = 900ms failure detection
```

---

## 10. Summary

| Tool | Mode | Failover | Load Distribution |
|------|------|---------|-----------------|
| MetalLB L2 | ARP/NDP | ~10s (leader election) | Single node (ingress point) |
| MetalLB BGP | BGP routes | <1s (with BFD) | ECMP across nodes |
| kube-vip | ARP/BGP | VRRP ~1s | Single or ECMP |

---

**Next:** [Lesson 18 — Cloud Provider Load Balancers](20-cloud-load-balancers.md)
