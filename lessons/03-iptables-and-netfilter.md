# Lesson 03 — iptables and Netfilter Architecture

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 02 — IP Routing and Forwarding](02-ip-routing-and-forwarding.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Run all commands inside minikube
minikube ssh

# See kube-proxy iptables rules live
sudo iptables -t nat -L KUBE-SERVICES -n --line-numbers | head -20
```

---

## Why This Matters

kube-proxy (in its default mode) translates Kubernetes Services into iptables rules. Even with Cilium's eBPF bypass, iptables is still the fallback for many clusters, and understanding the netfilter hook points is essential for debugging dropped packets, NAT issues, and policy enforcement.

---

## 1. Netfilter Hook Points

The Linux kernel's **netfilter framework** intercepts packets at five hook points in the network stack:

```
                      ┌─────────────┐
                      │  PREROUTING │◄── Incoming packets (before routing decision)
                      └──────┬──────┘
                             │
              ┌──────────────▼──────────────┐
              │        Routing Decision      │
              └───┬─────────────────────┬───┘
                  │                     │
           ┌──────▼──────┐       ┌──────▼──────┐
           │   INPUT     │       │   FORWARD   │
           │(to local)   │       │(pass-thru)  │
           └──────┬──────┘       └──────┬──────┘
                  │                     │
           ┌──────▼──────┐       ┌──────▼──────┐
           │  Local Process       │  POSTROUTING│◄── Outgoing
           └──────┬──────┘       └─────────────┘
                  │
           ┌──────▼──────┐
           │  OUTPUT     │
           └──────┬──────┘
                  │
           ┌──────▼──────┐
           │  POSTROUTING│◄── After routing decision
           └─────────────┘
```

---

## 2. Tables and Chains

iptables organizes rules into **tables** (purpose) and **chains** (hook points).

| Table | Purpose | Built-in Chains |
|-------|---------|-----------------|
| `filter` | Allow / Drop / Reject | INPUT, FORWARD, OUTPUT |
| `nat` | SNAT / DNAT | PREROUTING, OUTPUT, POSTROUTING |
| `mangle` | Modify headers (TTL, TOS, marks) | All 5 |
| `raw` | Skip conntrack | PREROUTING, OUTPUT |

Processing order at PREROUTING: `raw → mangle → nat → filter`

---

## 3. kube-proxy iptables Rules

When you create a Service of type ClusterIP, kube-proxy writes rules like this:

```
ClusterIP: 10.96.0.1  Port: 80
Backend Pods: 10.244.0.5:8080, 10.244.1.3:8080
```

```bash
# Inspect kube-proxy chains
iptables -t nat -L KUBE-SERVICES -n --line-numbers
iptables -t nat -L KUBE-SVC-XXXX -n       # per-Service chain
iptables -t nat -L KUBE-SEP-XXXX -n       # per-Endpoint chain
```

Packet flow for a ClusterIP request:
```
Pod sends to 10.96.0.1:80
  → PREROUTING → nat/KUBE-SERVICES
    → matches KUBE-SVC-XXXX (the service chain)
      → statistic match (round-robin) → KUBE-SEP-YYY (endpoint 1)
        → DNAT to 10.244.0.5:8080
  → routing decision: forward to 10.244.0.5
  → POSTROUTING: MASQUERADE if leaving the node
```

---

## 4. Common iptables Commands

```bash
# List rules with line numbers and no DNS resolution
iptables -t nat -L -n --line-numbers -v

# Save and restore rules
iptables-save > /etc/iptables/rules.v4
iptables-restore < /etc/iptables/rules.v4

# Append a rule to FORWARD chain (allow pod traffic)
iptables -A FORWARD -s 10.244.0.0/16 -j ACCEPT
iptables -A FORWARD -d 10.244.0.0/16 -j ACCEPT

# Insert a logging rule at position 1 (before DROP)
iptables -I INPUT 1 -p tcp --dport 80 -j LOG --log-prefix "HTTP-IN: "

# Count packets matching a rule
iptables -t filter -L FORWARD -v -n

# Flush all rules (DANGEROUS — locks you out if no default ACCEPT)
# iptables -F

# Delete a specific chain
iptables -t nat -F KUBE-SVC-XXXX
iptables -t nat -X KUBE-SVC-XXXX
```

---

## 5. NAT in Kubernetes

### DNAT — ClusterIP to Pod IP
Translates a virtual service IP to a real pod IP. Done in PREROUTING (for traffic arriving at the node) and OUTPUT (for traffic from local pods).

### SNAT / MASQUERADE — Pod to External
When a pod sends traffic to the internet, the pod IP must be replaced with the node's IP (since pod IPs are not routable externally).

```bash
# kube-proxy adds this for pod → external traffic
iptables -t nat -A POSTROUTING -s 10.244.0.0/16 ! -d 10.244.0.0/16 -j MASQUERADE

# Check MASQUERADE rules
iptables -t nat -L POSTROUTING -n -v | grep -i masq
```

### Hairpin NAT
When a pod accesses its own service IP, the reply must loop back. kube-proxy handles this with MASQUERADE in POSTROUTING when src and dst are both pods.

---

## 6. Conntrack — Connection Tracking

Netfilter tracks connection state so reply packets can be associated with their request.

```bash
# View conntrack table
conntrack -L
conntrack -L --proto tcp --state ESTABLISHED

# Monitor new connections
conntrack -E --event-mask NEW

# Table size (critical to tune for high-throughput clusters)
cat /proc/sys/net/netfilter/nf_conntrack_max
sysctl -w net.netfilter.nf_conntrack_max=1000000

# Current usage
cat /proc/sys/net/netfilter/nf_conntrack_count

# Bucket count (hash table size)
cat /proc/sys/net/netfilter/nf_conntrack_buckets
```

Conntrack exhaustion causes **silent packet drops** — one of the most common and hardest-to-diagnose issues in production Kubernetes clusters.

```bash
# Check for conntrack drops
dmesg | grep -i "nf_conntrack: table full"
cat /proc/net/stat/nf_conntrack | awk '{print $1, $2, $3}'
```

---

## 7. ipset

kube-proxy uses `ipset` for efficient lookups when there are many endpoints. Instead of thousands of individual iptables rules, one rule matches against an ipset.

```bash
# List all ipsets
ipset list

# kube-proxy creates sets like KUBE-CLUSTER-IP, KUBE-NODE-PORT-TCP
ipset list KUBE-CLUSTER-IP

# Manual ipset
ipset create my-pods hash:ip
ipset add my-pods 10.244.0.5
ipset add my-pods 10.244.1.3

iptables -A INPUT -m set --match-set my-pods src -j ACCEPT
```

---

## 8. IPVS Mode (kube-proxy alternative)

IPVS (IP Virtual Server) is a kernel-level L4 load balancer — faster than iptables for large numbers of services.

```bash
# Check if kube-proxy is using IPVS
kubectl get cm -n kube-system kube-proxy -o yaml | grep mode
# mode: ipvs

# Inspect IPVS rules
ipvsadm -L -n
ipvsadm -L -n --stats

# Example output:
# TCP  10.96.0.1:80 rr
#   -> 10.244.0.5:8080           Masq    1      0          0
#   -> 10.244.1.3:8080           Masq    1      0          0
```

IPVS advantages over iptables:
- O(1) lookup (hash table) vs O(n) iptables chain traversal
- Native load-balancing algorithms: rr, lc, dh, sh, lblc, lblcr
- Lower CPU for large clusters (1000+ services)

---

## 9. eBPF and the Post-iptables Era

Cilium replaces kube-proxy's iptables rules with eBPF programs attached directly to network interfaces:

```bash
# Check kube-proxy replacement mode in Cilium
cilium status | grep KubeProxy

# View eBPF-based service entries
cilium service list

# View NAT table in BPF
cilium bpf nat list
```

Benefits: no conntrack for pod-to-pod, no SNAT for intra-cluster traffic, lower latency.

---

## 10. Debugging Packet Flow

```bash
# Trace a packet through the netfilter hooks (requires kernel module)
modprobe nf_log_ipv4
iptables -t raw -A PREROUTING -s 10.244.0.5 -j TRACE
iptables -t raw -A OUTPUT -d 10.244.0.5 -j TRACE
# Then watch kernel logs
dmesg -wH | grep TRACE

# Count drops per chain
iptables -t filter -L FORWARD -v -n
# Pkts in and out columns show traffic; zero out means matching but passing

# Watch iptables rule hit counts live
watch -n1 'iptables -t nat -L KUBE-SERVICES -v -n | head -30'
```

---

## 11. Summary

| Component | Role in Kubernetes |
|-----------|--------------------|
| nat/PREROUTING | DNAT service IP → pod IP |
| nat/POSTROUTING | SNAT pod IP → node IP (MASQUERADE) |
| filter/FORWARD | Allow/deny routed pod traffic |
| conntrack | Session state for NAT reverse translation |
| ipset | Efficient IP group matching for endpoints |
| IPVS | Fast kernel load balancing (kube-proxy IPVS mode) |
| eBPF (Cilium) | Bypass iptables entirely at the socket/TC layer |

---

**Next:** [Lesson 04 — Network Namespaces Deep Dive](04-network-namespaces-deep-dive.md)
