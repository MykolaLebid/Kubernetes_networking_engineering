# Lesson 02 — IP Routing and Forwarding in Linux

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 01 — Linux Networking Fundamentals](01-linux-networking-fundamentals.md)  
> **Duration:** ~2 hours

---

## Practice Setup

```bash
# Run all commands inside minikube
minikube ssh

# View live pod routes — these are real Calico-programmed routes
ip route show
```

---

## Why This Matters

Kubernetes pod-to-pod traffic across nodes is fundamentally an IP routing problem. CNI plugins solve it differently (BGP, VXLAN, direct routes), but they all manipulate the Linux routing table. Knowing how the kernel makes forwarding decisions lets you trace any packet end-to-end.

---

## 1. How Linux Routes a Packet

When a process sends a packet, the kernel performs a **longest-prefix match (LPM)** lookup:

1. Check local routing table (table 255) — is the destination on this host?
2. Check the main routing table (table 254) — find the most specific matching prefix.
3. If nothing matches, use the default route (`0.0.0.0/0`).
4. Resolve the next-hop MAC via ARP.
5. Hand off to the outbound interface driver.

```bash
# Trace which route would be chosen for a destination
ip route get 10.244.1.5
# 10.244.1.5 via 192.168.1.20 dev eth0 src 192.168.1.10
```

---

## 2. Routing Tables and Rules

Linux supports **multiple routing tables** selected by policy rules.

```bash
# List policy rules (evaluated top-to-bottom)
ip rule list
# 0:      from all lookup local       ← loopback, broadcast
# 32766:  from all lookup main        ← normal routes
# 32767:  from all lookup default     ← fallback

# Show a specific table
ip route show table main
ip route show table local

# Add a rule: traffic from pod CIDR uses table 100
ip rule add from 10.244.0.0/16 lookup 100 priority 100
ip route add default via 192.168.1.1 table 100
```

Calico uses policy routing to steer pod traffic to the correct veth without IP masquerading.

---

## 3. Static Routes

```bash
# Host route — single destination IP (pod-specific routes in Calico/Cilium)
ip route add 10.244.1.5/32 via 192.168.1.20

# Network route — entire remote pod CIDR (Flannel host-gw mode)
ip route add 10.244.1.0/24 via 192.168.1.20 dev eth0

# ECMP — equal-cost multi-path (multiple next-hops)
ip route add 10.244.1.0/24 nexthop via 192.168.1.20 nexthop via 192.168.1.21

# Delete a route
ip route del 10.244.1.0/24 via 192.168.1.20
```

---

## 4. IP Forwarding

A Linux node acts as a router only when `ip_forward` is enabled.

```bash
# Check
cat /proc/sys/net/ipv4/ip_forward

# Enable temporarily
sysctl -w net.ipv4.ip_forward=1

# Persist across reboots
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-ip-forward.conf
sysctl --system
```

Without this, pods on node A cannot reach pods on node B even if routes exist — the node will silently drop transit packets.

---

## 5. Routing in Different CNI Modes

### Flannel host-gw (pure L3, no overlay)
```
Node A (192.168.1.10) has pod CIDR 10.244.0.0/24
Node B (192.168.1.20) has pod CIDR 10.244.1.0/24

On Node A:
  ip route add 10.244.1.0/24 via 192.168.1.20   ← added by Flannel

On Node B:
  ip route add 10.244.0.0/24 via 192.168.1.10   ← added by Flannel
```
Requires all nodes to be on the same L2 segment (same VLAN/subnet).

### Calico with BGP
Calico runs `bird` (BGP daemon) on each node. Nodes peer with each other (or a Route Reflector) and exchange `/32` host routes for each pod.
```bash
# View BGP peers
calicoctl node status

# View routes propagated by Calico
ip route show | grep bird
```

### Cilium native routing
Cilium programs the kernel routing table directly using BPF hooks. No separate daemon needed.
```bash
cilium status
cilium bpf tunnel list   # empty in native routing mode
```

---

## 6. ECMP and Hashing

For high-availability setups, multiple paths to the same destination can be load-balanced.

```bash
# Install iproute2 with ECMP support (Linux 3.6+)
ip route add 10.244.0.0/16 \
  nexthop via 192.168.1.10 weight 1 \
  nexthop via 192.168.1.11 weight 1

# Hash is per-flow by default (src IP, dst IP, protocol, ports)
# Check hash policy
cat /proc/sys/net/ipv4/fib_multipath_hash_policy
# 0 = L3, 1 = L4 (recommended for Kubernetes)
sysctl -w net.ipv4.fib_multipath_hash_policy=1
```

---

## 7. Troubleshooting Routing

```bash
# Is ip_forward on?
sysctl net.ipv4.ip_forward

# Which route will be used?
ip route get 10.244.3.7

# Is there a blackhole route blocking traffic?
ip route show | grep blackhole

# Watch routing table changes in real time
ip monitor route

# Is the packet leaving the right interface?
# Use tcpdump to verify
tcpdump -i eth0 -n 'host 10.244.3.7'
tcpdump -i cali1234abcd -n 'host 10.244.3.7'

# Check if kernel is dropping forwarded packets
watch -n1 'cat /proc/net/stat/rt_cache'
netstat -s | grep -i "forwarded\|route"
```

---

## 8. Cloud Provider Routing Differences

### AWS VPC
- Each EC2 instance has a VPC route table entry pointing to its ENI.
- **Pod routing options:**
  - AWS VPC CNI: pods get real VPC IPs via secondary ENI IPs — no overlay needed, routes are in the VPC route table.
  - Overlay CNI (Flannel/Calico): pods use a secondary CIDR; traffic is encapsulated before leaving the node.
- Requires disabling the **Source/Destination Check** on the EC2 instance when using non-VPC pod IPs.

### GCP VPC
- GCP uses a software-defined distributed router. Route tables are per-VPC and global.
- Kubernetes on GKE injects per-node pod CIDR routes automatically.
- Google's VPC supports custom-mode subnets with alias IP ranges for pods (similar to AWS VPC CNI).

### Azure VNet
- Azure CNI gives pods Azure VNet IPs from the subnet address space.
- Kubenet (the basic option) uses a UDR (User Defined Route) for pod CIDRs — similar to Flannel host-gw.

---

## 9. Hands-On Lab: Cross-Namespace Routing

Simulate two nodes routing pods to each other (no overlay, pure L3).

```bash
# Two "nodes" = two namespaces with veth links to the host
ip netns add node1
ip netns add node2

# node1 veth
ip link add veth-n1 type veth peer name veth-n1-host
ip link set veth-n1 netns node1
ip link set veth-n1-host up
ip addr add 192.168.1.1/24 dev veth-n1-host
ip netns exec node1 ip addr add 192.168.1.10/24 dev veth-n1
ip netns exec node1 ip link set veth-n1 up
ip netns exec node1 ip link set lo up
ip netns exec node1 ip route add default via 192.168.1.1

# node2 veth
ip link add veth-n2 type veth peer name veth-n2-host
ip link set veth-n2 netns node2
ip link set veth-n2-host up
ip addr add 192.168.1.2/24 dev veth-n2-host
ip netns exec node2 ip addr add 192.168.1.20/24 dev veth-n2
ip netns exec node2 ip link set veth-n2 up
ip netns exec node2 ip link set lo up
ip netns exec node2 ip route add default via 192.168.1.2

# "CNI" static routes — each node knows remote pod CIDR
ip netns exec node1 ip route add 10.244.1.0/24 via 192.168.1.20
ip netns exec node2 ip route add 10.244.0.0/24 via 192.168.1.10

# Enable forwarding on host
sysctl -w net.ipv4.ip_forward=1

# Test (ping from node1's pod CIDR perspective)
ip netns exec node1 ping -c3 -I 10.244.0.1 10.244.1.1
```

---

## 10. Summary

| Concept | Command |
|---------|---------|
| Show routing table | `ip route show` |
| Test routing decision | `ip route get <dst>` |
| Add static route | `ip route add <prefix> via <gw>` |
| Enable forwarding | `sysctl net.ipv4.ip_forward=1` |
| Monitor route changes | `ip monitor route` |
| Multi-path hash policy | `net.ipv4.fib_multipath_hash_policy=1` |

---

**Next:** [Lesson 03 — iptables and Netfilter Architecture](03-iptables-and-netfilter.md)
