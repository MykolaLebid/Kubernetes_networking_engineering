# Lesson 13 — CoreDNS and Service Discovery

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 12 — Kubernetes Services](12-kubernetes-services-kube-proxy.md)  
> **Duration:** ~2 hours

---

## Why This Matters

DNS is how services find each other in Kubernetes. CoreDNS runs as the cluster DNS server and handles all `*.cluster.local` lookups. Misconfigured DNS is one of the most common and confusing connectivity problems — slow queries, timeouts, and "name not resolved" errors all trace back here.

---

## 1. CoreDNS Architecture

```
Pod → resolv.conf → CoreDNS ClusterIP (10.96.0.10)
         ↓
  CoreDNS Pod (Deployment, 2+ replicas)
         ↓
  Corefile: plugins chain
  ├── kubernetes plugin → answer *.cluster.local
  ├── forward plugin → forward external queries to upstream
  └── cache plugin → cache responses
```

```bash
# CoreDNS deployment
kubectl get deploy -n kube-system coredns
kubectl get pods -n kube-system -l k8s-app=kube-dns

# CoreDNS service IP
kubectl get svc -n kube-system kube-dns
# NAME       TYPE        CLUSTER-IP   PORT(S)
# kube-dns   ClusterIP   10.96.0.10   53/UDP,53/TCP
```

---

## 2. Pod DNS Configuration

Every pod gets a `/etc/resolv.conf` injected by kubelet:

```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

The **search domains** allow short names:
- `web` → tries `web.default.svc.cluster.local` first (if ndots ≥ 5 dots)
- `web.default` → tries `web.default.svc.cluster.local`
- `web.default.svc.cluster.local` → resolves directly

```bash
# Check pod's resolv.conf
kubectl exec -it <pod> -- cat /etc/resolv.conf
```

---

## 3. DNS Name Formats

```
<service>.<namespace>.svc.<cluster-domain>

Examples:
  web.default.svc.cluster.local          ← ClusterIP service
  db-0.db.default.svc.cluster.local      ← StatefulSet pod (via headless svc)
  10-244-0-5.default.pod.cluster.local   ← pod IP reverse (rarely used)
```

```bash
# Test DNS from inside the cluster
kubectl run -it --rm dns-test --image=nicolaka/netshoot -- \
  nslookup web.default.svc.cluster.local 10.96.0.10

kubectl run -it --rm dns-test --image=nicolaka/netshoot -- \
  dig web.default.svc.cluster.local @10.96.0.10 +short
```

---

## 4. Corefile Configuration

```bash
# View current CoreDNS config
kubectl get cm -n kube-system coredns -o yaml
```

Default Corefile:
```
.:53 {
    errors
    health {
        lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
        max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

---

## 5. Custom DNS Configurations

### Forward specific domains to custom DNS
```
# Add to Corefile — route internal domain to corporate DNS
corp.example.com:53 {
    forward . 10.100.0.53
    cache 30
}
```

```bash
kubectl edit cm -n kube-system coredns
# Add stanzas before the closing }
# CoreDNS auto-reloads on ConfigMap change (reload plugin)
```

### Stub zones for split-horizon DNS
```
# Different answers for internal vs external
internal.example.com:53 {
    file /etc/coredns/db.internal.example.com
}
```

### Hosts file entries
```
.:53 {
    hosts /etc/coredns/customhosts {
        10.100.0.5  legacy-server.example.com
        fallthrough
    }
    # ... rest of config
}
```

---

## 6. ndots and Performance

The default `ndots:5` causes each short name to be tried against all search domains before resolving as a FQDN. For a name like `api`, this generates up to 6 DNS queries:

```
1. api.default.svc.cluster.local
2. api.svc.cluster.local
3. api.cluster.local
4. api.example.com (if set)
5. api.                (FQDN attempt)
```

For external names, this adds latency. Fix:

```yaml
# Option 1: Use FQDNs in app config (add trailing dot)
# http://external-api.example.com./path

# Option 2: Per-pod dnsConfig
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "1"   # only 1 dot needed to skip search domain expansion
      - name: single-request-reopen  # avoid UDP race condition

# Option 3: Tune globally (affects all new pods)
kubectl edit cm -n kube-system kubelet-config
# resolvConf: custom resolv.conf with ndots:1
```

---

## 7. NodeLocal DNSCache

NodeLocal DNSCache runs a DNS cache on each node, reducing latency and CoreDNS load.

```
Pod → 169.254.20.10 (node-local cache)
         ↓ (cache miss)
      CoreDNS
```

```bash
# Install NodeLocal DNSCache
# https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
kubectl apply -f nodelocaldns.yaml

# Verify
kubectl get pods -n kube-system -l k8s-app=node-local-dns

# NodeLocal cache listens on the link-local address
ip addr show nodelocaldns
# 169.254.20.10/32

# Pods must have this in their resolv.conf nameserver
kubectl exec -it <pod-with-nodelocaldns> -- cat /etc/resolv.conf
# nameserver 169.254.20.10
```

Benefits:
- ~3ms p99 → ~0.3ms p99 for cached queries
- Reduces UDP races with TCP fallback
- Keeps CoreDNS pods from being overwhelmed

---

## 8. CoreDNS Metrics

```bash
# CoreDNS exposes Prometheus metrics on port 9153
kubectl port-forward -n kube-system svc/kube-dns 9153:9153 &
curl http://localhost:9153/metrics | grep -E "coredns_dns_requests|coredns_dns_responses|coredns_cache"

# Key metrics to watch:
# coredns_dns_requests_total         — query rate
# coredns_dns_responses_total        — response rate by rcode
# coredns_dns_request_duration_seconds — latency
# coredns_cache_hits_total           — cache effectiveness
# coredns_forward_requests_total     — upstream query rate
```

---

## 9. Troubleshooting DNS

```bash
# Step 1: Is CoreDNS running and healthy?
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns | grep -E "WARN|ERROR"

# Step 2: Can a pod reach CoreDNS?
kubectl run -it --rm dns-debug --image=nicolaka/netshoot -- \
  nc -vzu 10.96.0.10 53

# Step 3: Does a simple lookup work?
kubectl run -it --rm dns-debug --image=nicolaka/netshoot -- \
  nslookup kubernetes.default.svc.cluster.local

# Step 4: Does external DNS work?
kubectl run -it --rm dns-debug --image=nicolaka/netshoot -- \
  nslookup google.com

# Step 5: Check CoreDNS logs with query logging enabled
kubectl edit cm -n kube-system coredns
# Add: log  (inside the .:53 block)

# Step 6: DNS timeout symptoms
# "dial tcp: lookup <name>: i/o timeout"
# → check kube-dns iptables rules exist
iptables -t nat -L KUBE-SERVICES -n | grep 10.96.0.10

# Common issues:
# 1. ndots:5 causing slow external resolution → lower ndots
# 2. CoreDNS OOMKilled → increase memory limits
# 3. conntrack table full → UDP race condition → use TCP or NodeLocal DNSCache
# 4. Missing forward DNS → check upstream in Corefile
# 5. Pod not in correct namespace → use FQDN
```

---

## 10. DNS on Bare Metal vs Cloud

### Bare Metal
- CoreDNS forwards external queries to your on-prem DNS servers
- Configure `forward . <corporate-dns-ip>` in Corefile
- Split-horizon DNS for reaching internal services by their corporate names

### Cloud
- CoreDNS forwards to the cloud's internal resolver (169.254.169.253 on AWS, 169.254.169.254 on GCP)
- Cloud resolver handles VPC DNS (`*.internal`, `*.compute.internal`)
- For custom domains, configure stub zones or forward to Route53/Cloud DNS

```bash
# AWS: check the VPC DNS resolver
# Default: 169.254.169.253 or VPC_CIDR + 2 (e.g., 10.0.0.2)
kubectl get cm -n kube-system coredns -o yaml | grep forward
```

---

## 11. Summary

| Concept | Detail |
|---------|--------|
| CoreDNS service IP | `10.96.0.10` (kube-dns) |
| Pod resolv.conf | Injected by kubelet with search domains + ndots:5 |
| Service DNS format | `<svc>.<ns>.svc.cluster.local` |
| ndots:5 problem | Multiple fallback queries for external names |
| NodeLocal DNSCache | Per-node cache at 169.254.20.10 — reduces latency |
| Custom forward | Stub zones in Corefile for internal domains |

---

**Next:** [Lesson 14 — Network Policies: Microsegmentation](14-network-policies.md)
