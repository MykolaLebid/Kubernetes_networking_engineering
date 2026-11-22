# Lesson 13 — Kubernetes Services and kube-proxy

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 03 — iptables](03-iptables-and-netfilter.md), [Lesson 02 — IP Routing](02-ip-routing-and-forwarding.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — minikube Linux node
minikube ssh
sudo iptables -t nat -L KUBE-SERVICES | head -20
sudo iptables -t nat -L KUBE-NODEPORTS 2>/dev/null | head -10
ipvsadm -Ln 2>/dev/null | head -20  # if IPVS mode

# Terminal 2 — Mac (kubectl)
kubectl get svc -A
kubectl get endpointslices -A | head -10
kubectl get cm -n kube-system kube-proxy -o yaml | grep mode
```

---

## Why This Matters

Services are Kubernetes' fundamental service-discovery and load-balancing abstraction. Every application you deploy needs them. Understanding how ClusterIP, NodePort, and LoadBalancer work at the packet level lets you debug connectivity issues, tune performance, and choose the right service type for each use case.

---

## 1. The Service Problem

Pods have ephemeral IPs that change on restart. Services provide a stable virtual IP (VIP) that:
- Never changes while the service exists
- Automatically load-balances across healthy pod replicas
- Is discoverable via DNS

---

## 2. Service Types

### ClusterIP (default)
Virtual IP reachable only from within the cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP      # default
  selector:
    app: web
  ports:
    - port: 80         # service port
      targetPort: 8080 # pod port
```

```bash
# Service gets a ClusterIP from the service CIDR
kubectl get svc web
# NAME   TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
# web    ClusterIP   10.96.42.10   <none>        80/TCP    1m
```

### NodePort
Exposes the service on a static port on every node's IP.

```yaml
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080    # 30000-32767 range
```

```bash
# Reachable from outside:
curl http://<any-node-ip>:30080
```

### LoadBalancer
Provisions an external load balancer (cloud LB or MetalLB on bare metal).

```yaml
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
```

```bash
kubectl get svc web
# NAME   TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)        AGE
# web    LoadBalancer   10.96.42.10   203.0.113.100    80:30080/TCP   2m
```

### ExternalName
DNS CNAME alias to an external hostname.

```yaml
spec:
  type: ExternalName
  externalName: api.example.com
```

### Headless Service
No ClusterIP — DNS returns individual pod IPs.

```yaml
spec:
  clusterIP: None   # headless
  selector:
    app: db
```

```bash
# DNS returns all pod IPs directly
kubectl exec -it test -- nslookup db.default.svc.cluster.local
# Server:    10.96.0.10
# Address:   10.96.0.10:53
# Name:  db.default.svc.cluster.local
# Address: 10.244.0.5   ← pod IPs directly
# Address: 10.244.1.3
```

Used by StatefulSets so each pod is addressable by name: `db-0.db.default.svc.cluster.local`.

---

## 3. Endpoints and EndpointSlices

The Service controller watches pods matching the selector and creates Endpoints.

```bash
# View endpoints
kubectl get endpoints web
# NAME   ENDPOINTS                       AGE
# web    10.244.0.5:8080,10.244.1.3:8080  5m

# Modern: EndpointSlices (default since K8s 1.21)
kubectl get endpointslices -l kubernetes.io/service-name=web
kubectl get endpointslice web-xxxxx -o yaml
```

EndpointSlices cap at 100 endpoints per slice to reduce kube-proxy update overhead.

---

## 4. kube-proxy Mechanics (iptables mode)

kube-proxy watches Services and Endpoints, then programs iptables rules.

```bash
# View kube-proxy mode
kubectl get cm -n kube-system kube-proxy -o yaml | grep mode

# Trace the iptables chain for a service
# Service: 10.96.42.10:80 → pods 10.244.0.5:8080, 10.244.1.3:8080

# Entry chain
iptables -t nat -L KUBE-SERVICES -n | grep 10.96.42.10
# KUBE-SVC-XXXX  tcp  10.96.42.10:80

# Service chain (round-robin via probabilistic match)
iptables -t nat -L KUBE-SVC-XXXX -n
# KUBE-SEP-AAAA  all  --  statistic mode random probability 0.50000000000
# KUBE-SEP-BBBB  all  --  (second endpoint, 50% chance)

# Endpoint chain (DNAT)
iptables -t nat -L KUBE-SEP-AAAA -n
# DNAT  tcp  --  to:10.244.0.5:8080
```

### iptables DNAT Chain: ClusterIP to Pod

```
Client pod (10.244.1.5) → Service ClusterIP (10.96.0.10:80)

PREROUTING / OUTPUT (nat table):
  │
  ▼
KUBE-SERVICES
  ├─ match dst=10.96.0.10, dport=80 ──► KUBE-SVC-XXXXHASH
  │                                          │
  │                              ┌───────────┴───────────────┐
  │                              │  Probabilistic selection  │
  │                              │  (1/N each SEP)           │
  │                     ─33%──►  KUBE-SEP-AAA  → DNAT → 10.244.0.5:8080
  │                     ─33%──►  KUBE-SEP-BBB  → DNAT → 10.244.0.6:8080
  │                     ─33%──►  KUBE-SEP-CCC  → DNAT → 10.244.2.1:8080
  │
  ├─ match dst=10.96.0.1, dport=443 ──► KUBE-SVC-kubernetes
  └─ default: KUBE-NODEPORTS (checks dport in NodePort range 30000-32767)

After DNAT: packet has real pod IP, routed normally to destination node.
POSTROUTING MASQUERADE ensures return traffic comes back through this node.

IPVS mode replaces all this with kernel hash tables — O(1) vs O(N) lookup.
```

---

## 5. kube-proxy IPVS Mode

IPVS is a kernel load balancer — faster and more scalable than iptables.

```bash
# Enable IPVS mode
kubectl edit cm -n kube-system kube-proxy
# mode: "ipvs"
# ipvs:
#   scheduler: "rr"  # rr, lc, dh, sh, lblc, lblcr

# View IPVS rules
ipvsadm -L -n
# TCP  10.96.42.10:80 rr
#   -> 10.244.0.5:8080           Masq    1      0          0
#   -> 10.244.1.3:8080           Masq    1      0          0

# IPVS maintains a dummy interface (kube-ipvs0) for all ClusterIPs
ip addr show kube-ipvs0
```

---

## 6. External Traffic Policy

Controls how traffic from outside the cluster reaches pods.

```yaml
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local    # or Cluster (default)
```

**Cluster (default):**
- Traffic can be forwarded to pods on any node
- Source IP is replaced with the node IP (SNAT)
- Load balances evenly across all pods

**Local:**
- Traffic only goes to pods on the node receiving the packet
- Source IP is preserved (no SNAT)
- Load balancer must do health checking per-node
- Nodes with no pods return unhealthy

```bash
# Check if a node has local endpoints
kubectl get endpointslice -l kubernetes.io/service-name=web -o yaml | \
  grep -A5 "nodeName"
```

---

## 7. Service Topology and Traffic Distribution

```yaml
# Traffic distribution hints (K8s 1.27+)
spec:
  trafficDistribution: PreferClose  # prefer same zone/node
```

```yaml
# Topology spread constraints for even pod distribution
spec:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: web
```

---

## 8. Session Affinity

Stick sessions to the same pod (useful for stateful apps without proper session sharing).

```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600
```

iptables implementation: uses `--recent` module to track source IPs and always DNAT to the same endpoint.

---

## 9. Service Debug Toolkit

```bash
# 1. Can we reach the ClusterIP from inside a pod?
kubectl run -it --rm debug --image=nicolaka/netshoot -- \
  curl -v http://10.96.42.10:80

# 2. Does DNS resolve the service name?
kubectl run -it --rm debug --image=nicolaka/netshoot -- \
  nslookup web.default.svc.cluster.local

# 3. Are there healthy endpoints?
kubectl get endpoints web
# If ENDPOINTS is <none>, no pods match the selector

# 4. Does the selector match pods?
kubectl get pods -l app=web

# 5. Are pods ready?
kubectl get pods -l app=web -o wide
# READY column must be 1/1

# 6. Watch kube-proxy logs
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50 -f

# 7. Verify iptables rules exist
iptables -t nat -S | grep 10.96.42.10

# 8. Test NodePort from outside
curl http://<node-ip>:30080
```

---

## 10. Services on Bare Metal vs Cloud

### Bare Metal
- **ClusterIP and NodePort** work identically
- **LoadBalancer** needs MetalLB or kube-vip (no cloud controller)
- Use BGP mode MetalLB to advertise VIPs to upstream router

### AWS EKS
```yaml
# NLB with IP mode (pod-level target registration)
annotations:
  service.beta.kubernetes.io/aws-load-balancer-type: "external"
  service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
```

### GKE
```yaml
# Internal L4 LB
annotations:
  networking.gke.io/load-balancer-type: "Internal"
```

### AKS
```yaml
# Internal LB
annotations:
  service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

---

## 11. Summary

| Type | Reachable From | IP Assigned |
|------|---------------|-------------|
| ClusterIP | Inside cluster | Service CIDR |
| NodePort | Outside (via node IP) | Service CIDR + node port |
| LoadBalancer | Outside (via LB IP) | External IP from cloud/MetalLB |
| ExternalName | Inside cluster | DNS CNAME (no IP) |
| Headless | Inside cluster (pod IPs) | None (clusterIP: None) |

---

**Next:** [Lesson 14 — CoreDNS and Service Discovery](14-coredns-service-discovery.md)
