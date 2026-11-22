# Lesson 05 — VXLAN and Overlay Networks

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 02 — IP Routing and Forwarding](02-ip-routing-and-forwarding.md)  
> **Duration:** ~2 hours

---

## Practice Setup

```bash
# Two terminals:
# Terminal 1 — minikube Linux node
minikube ssh
ip link show | grep -E "vxlan|tunl|cali"

# Terminal 2 — Mac, kubectl
kubectl get pods -A -o wide   # see pod IPs and nodes
```

---

## Why This Matters

VXLAN is the most widely used overlay technology in Kubernetes. Flannel (default mode), Calico (non-BGP mode), Cilium (non-native mode), and Weave all use VXLAN or a similar encapsulation. Understanding VXLAN lets you diagnose MTU issues, performance problems, and cross-node connectivity failures.

---

## 1. The Problem Overlay Networks Solve

Kubernetes assigns pods IPs from a private CIDR (e.g., `10.244.0.0/16`). These IPs are not routable on the underlying physical network. Without overlays, cross-node pod traffic would need:
- Routes programmed on every physical switch/router (BGP), **or**
- VPC-level route tables updated for every node (cloud), **or**
- An overlay that wraps pod-IP packets inside routable packets.

Overlay networks choose the third option: **encapsulate first, route second**.

---

## 2. VXLAN Fundamentals

**VXLAN (Virtual eXtensible LAN)** encapsulates L2 Ethernet frames inside UDP packets.

```
┌────────────────────────────────────────────────────────┐
│  Outer Ethernet (node MAC → next-hop MAC)              │
│  Outer IP (node IP → remote node IP)                   │
│  Outer UDP (src: ephemeral, dst: 4789)                  │
│  VXLAN Header (8 bytes, VNI)                           │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Inner Ethernet (pod MAC → dst pod MAC)          │  │
│  │  Inner IP (pod IP → dst pod IP)                  │  │
│  │  Inner TCP/UDP/... (application payload)         │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

- VNI (VXLAN Network Identifier): 24-bit segment ID (like a VLAN ID but 16M segments)
- UDP port 4789 (IANA standard), sometimes 8472 (Flannel legacy)
- Each node has a **VTEP** (VXLAN Tunnel Endpoint) — a virtual NIC that handles encap/decap

---

## 3. Creating a VXLAN Interface

```bash
# Create a VXLAN interface (VTEP)
ip link add vxlan0 type vxlan \
  id 100 \            # VNI
  dstport 4789 \      # UDP port
  local 192.168.1.10 \ # local node IP (tunnel source)
  dev eth0            # interface to use for outer IP

ip link set vxlan0 up
ip addr add 10.244.0.1/16 dev vxlan0

# Check interface details
ip -d link show vxlan0
```

---

## 4. VXLAN FDB (Forwarding Database)

The VTEP needs to know which remote node has which pod MAC address.

```bash
# View the VXLAN FDB
bridge fdb show dev vxlan0

# Output example:
# 00:00:00:00:00:00 dst 192.168.1.20 self permanent  ← flood to this VTEP
# aa:bb:cc:dd:ee:01 dst 192.168.1.20 self            ← specific pod MAC

# Add a unicast FDB entry (Flannel/Calico do this via their daemons)
bridge fdb add aa:bb:cc:dd:ee:01 dev vxlan0 dst 192.168.1.20

# Add an anycast entry (flood unknown MACs to all VTEPs)
bridge fdb add 00:00:00:00:00:00 dev vxlan0 dst 192.168.1.20
bridge fdb add 00:00:00:00:00:00 dev vxlan0 dst 192.168.1.30
```

Flannel uses etcd/Kubernetes API to watch node CIDRs and program FDB entries via flood + learn or unicast.

---

## 5. Flannel VXLAN Mode — How It Works

```
Node A (192.168.1.10) podCIDR=10.244.0.0/24  flannel.1=10.244.0.0
Node B (192.168.1.20) podCIDR=10.244.1.0/24  flannel.1=10.244.1.0

Pod A (10.244.0.5) → Pod B (10.244.1.7)

1. Pod A sends packet: src=10.244.0.5 dst=10.244.1.7
2. Host routing: ip route → 10.244.1.0/24 via 10.244.1.0 dev flannel.1 onlink
3. flannel.1 (VTEP) encapsulates:
   - outer src IP: 192.168.1.10 (Node A)
   - outer dst IP: 192.168.1.20 (Node B, from FDB lookup)
   - UDP dst port: 8472
4. Physical network routes 192.168.1.10 → 192.168.1.20
5. Node B's flannel.1 decapsulates
6. Host routing: ip route → 10.244.1.7/32 dev cni0 (or directly to pod veth)
7. Packet delivered to Pod B
```

---

## 6. MTU — The Most Common VXLAN Problem

VXLAN adds **50 bytes** of overhead (outer Ethernet + IP + UDP + VXLAN header).

```
Physical NIC MTU: 1500 bytes
VXLAN overhead:    -50 bytes
Pod/container MTU: 1450 bytes
```

If pods use MTU 1500 (the default), large packets get fragmented or dropped (if DF bit set).

```bash
# Check MTU on VXLAN interface
ip link show flannel.1 | grep mtu

# Check pod-side MTU (inside pod namespace)
kubectl exec -it <pod> -- ip link show eth0 | grep mtu

# Test actual MTU with ping
kubectl exec -it <pod> -- ping -M do -s 1422 <other-pod-ip>
# -M do = don't fragment, -s = payload size
# 1422 + 28 (ICMP+IP headers) = 1450 ✓
# 1423 + 28 = 1451 → fragmented or dropped ✗

# Fix: set CNI MTU in ConfigMap (Flannel example)
kubectl edit cm -n kube-system kube-flannel-cfg
# NET_CONF_JSON: "MTU": 1450
```

Cloud environments may have different base MTU:
- AWS: 9001 (jumbo frames on most instance types) → pod MTU 8951
- GCP: 1460 (VPC default) → pod MTU 1410
- Azure: 1500 → pod MTU 1450
- On-prem with jumbo frames: 9000 → pod MTU 8950

---

## 7. Geneve — The Modern Alternative

Geneve (Generic Network Virtualization Encapsulation) is similar to VXLAN but with extensible headers. OVN and OpenShift use Geneve.

```bash
# Create a Geneve interface
ip link add geneve0 type geneve \
  id 100 \
  remote 192.168.1.20 \
  dstport 6081

ip link set geneve0 up
```

Cilium uses Geneve or VXLAN depending on configuration:
```bash
cilium config view | grep tunnel
# tunnel-protocol: vxlan  (or geneve)
```

---

## 8. Bare Metal vs Cloud Overlay Considerations

### Bare Metal
- Full control of MTU (configure jumbo frames end-to-end for best performance)
- Overlay overhead matters more at 10/25/100 GbE
- Consider native routing (BGP, host-gw) for performance-sensitive workloads
- Ensure UDP 4789/8472 is allowed on host firewall rules

```bash
# Allow VXLAN on firewall (if using ufw/iptables)
ufw allow 4789/udp
# or:
iptables -I INPUT -p udp --dport 4789 -j ACCEPT
```

### Cloud (AWS/GCP/Azure)
- VPC Security Groups / Firewall Rules must allow UDP 4789 between nodes
- NACLs (AWS) must allow it in both directions
- Cloud load balancers don't forward raw UDP 4789 — VXLAN must be node-to-node
- Some cloud providers offer native overlay bypass (AWS VPC CNI, GKE Dataplane v2)

```bash
# AWS: check Security Group allows VXLAN
aws ec2 describe-security-groups --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`4789`]'
```

---

## 9. Performance Tuning

```bash
# Enable hardware offload for VXLAN (if NIC supports it)
ethtool -k eth0 | grep tx-udp_tnl
# tx-udp_tnl-segmentation: on

# Enable checksum offload
ethtool -K eth0 tx-checksum-ip-generic on

# Increase UDP receive buffer for VTEP
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216

# Use RSS (Receive Side Scaling) so VXLAN decap is spread across CPUs
ethtool -l eth0
ethtool -L eth0 combined 8
```

---

## 10. Hands-On Lab: Manual VXLAN Tunnel

Build a VXLAN overlay between two Linux hosts (or VMs).

```bash
### On Host A (192.168.1.10)
ip link add vxlan10 type vxlan id 10 dstport 4789 \
  local 192.168.1.10 dev eth0
ip link set vxlan10 up
ip addr add 10.0.0.1/24 dev vxlan10

bridge fdb add 00:00:00:00:00:00 dev vxlan10 dst 192.168.1.20
ip route add 10.0.0.0/24 dev vxlan10

### On Host B (192.168.1.20)
ip link add vxlan10 type vxlan id 10 dstport 4789 \
  local 192.168.1.20 dev eth0
ip link set vxlan10 up
ip addr add 10.0.0.2/24 dev vxlan10

bridge fdb add 00:00:00:00:00:00 dev vxlan10 dst 192.168.1.10
ip route add 10.0.0.0/24 dev vxlan10

### Test (from Host A)
ping -c5 10.0.0.2

### Inspect encapsulated traffic
tcpdump -i eth0 -n udp port 4789 -X
```

---

## 11. Summary

| Concept | Detail |
|---------|--------|
| VXLAN overhead | 50 bytes → subtract from physical MTU |
| FDB | Maps pod MAC → remote node VTEP IP |
| Flannel VXLAN | Flood+learn or unicast FDB via Kubernetes API |
| Geneve | Extensible alternative, used by OVN/Cilium |
| MTU mismatch | Most common VXLAN-related packet drop cause |
| Cloud firewall | Must allow UDP 4789 between nodes |

---

## Online Resources

| Resource | Type | What you practice |
|----------|------|-------------------|
| [Killercoda Playground](https://killercoda.com/) | Free playground | Create VXLAN interfaces, inspect FDB, test encapsulation with `tcpdump` live |
| [iximiuz: Container Networking from Scratch](https://labs.iximiuz.com/tutorials/container-networking-from-scratch) | Free interactive lab | Covers overlay mechanics that explain why VXLAN is needed |

---

**Next:** [Lesson 06 — BGP Fundamentals for Kubernetes](06-bgp-fundamentals.md)
