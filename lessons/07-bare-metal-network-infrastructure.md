# Lesson 07 — Bare Metal Network Infrastructure for Kubernetes

> **Track:** Network Foundation — Bare Metal  
> **Prerequisites:** [Lesson 05 — VXLAN](05-vxlan-and-overlay-networks.md), [Lesson 06 — BGP](06-bgp-fundamentals.md)  
> **Duration:** ~3 hours

---

## Practice Setup

```bash
# Terminal 1 — minikube Linux node
minikube ssh
ip link show bonding_masters 2>/dev/null || echo "No bonding on this node"
bridge vlan show 2>/dev/null
ip link show type vlan

# Terminal 2 — Mac (kubectl)
kubectl get nodes -o wide
kubectl describe node minikube | grep -A5 "Addresses\|Capacity"
```

---

## Why This Matters

Deploying Kubernetes on bare metal gives you full control — and full responsibility. Unlike cloud providers, you must design and operate the physical network, switch configuration, NIC bonding, and load-balancer integration. Getting this right is what separates a stable production cluster from one that has mysterious packet drops.

---

## 1. Physical Network Topology

### Single Rack (small clusters, up to ~20 nodes)
```
       [Internet / Uplink]
              │
        [Core Switch]
              │
        [ToR Switch]  ← 10/25 GbE access ports
       /    |    |    \
   Node1 Node2 Node3 Node4
```

### Spine-Leaf (production, 20–1000+ nodes)
```
      [Spine1]   [Spine2]
       /   \       /   \
   [Leaf1][Leaf2][Leaf3][Leaf4]
     |||     |||     |||     |||
   Nodes   Nodes   Nodes   Nodes
```

Each Leaf uplinks to every Spine (full mesh). Nodes connect only to their Leaf. Provides predictable latency and no STP convergence issues.

Kubernetes recommendation: **Spine-Leaf with ECMP** — symmetric routing, no oversubscription bottleneck.

---

## 2. NIC Configuration and Bonding

### Single NIC (dev/small)
Simple but no redundancy.

### LACP Bond (802.3ad) — Recommended
```bash
# Check NIC speed and driver
ethtool eth0 | grep -E "Speed|Duplex|Link"
ethtool -i eth0 | grep driver

# Create a bond
ip link add bond0 type bond mode 802.3ad
ip link set eth0 master bond0
ip link set eth1 master bond0
ip link set bond0 up

# Verify bond status
cat /proc/net/bonding/bond0
# Active slaves, LACP state, link speeds
```

Switch side: configure the ports as a port-channel / LAG.

### SR-IOV (High Performance)
SR-IOV partitions a physical NIC into Virtual Functions (VFs), each passed directly into a pod or VM.

```bash
# Check SR-IOV capability
cat /sys/bus/pci/devices/<pci-addr>/sriov_totalvfs

# Enable 8 VFs
echo 8 > /sys/bus/pci/devices/<pci-addr>/sriov_numvfs

# VFs appear as additional PCI devices
lspci | grep -i ethernet
```

Kubernetes integration: use the SR-IOV Network Device Plugin + SR-IOV CNI for DPDK/low-latency workloads.

---

## 3. VLAN Design

VLANs segment traffic on the same physical switches. Common Kubernetes VLAN design:

| VLAN | Purpose |
|------|---------|
| 10 | Management (SSH, iDRAC/iLO, BMC) |
| 20 | Kubernetes node traffic (podCIDR routing, BGP) |
| 30 | Storage (Ceph, NFS) |
| 40 | Cluster internal (optional, for OOB monitoring) |

```bash
# Configure VLAN on a node interface
ip link add link eth0 name eth0.20 type vlan id 20
ip link set eth0.20 up
ip addr add 192.168.20.10/24 dev eth0.20

# Or configure the switch to present VLAN 20 untagged to the port (access port)
# Node then uses eth0 directly
```

Switch config (Cisco NX-OS example):
```
interface Ethernet1/1
  switchport mode access
  switchport access vlan 20
  spanning-tree port type edge
  no shutdown
```

---

## 4. MTU and Jumbo Frames

Production bare metal should use **jumbo frames (MTU 9000)** end-to-end.

```bash
# Set jumbo frames on NIC
ip link set eth0 mtu 9000

# Persist in network config (varies by distro)
# /etc/netplan/01-netcfg.yaml (Ubuntu)
network:
  ethernets:
    eth0:
      mtu: 9000

# Verify end-to-end (ping with DF bit)
ping -M do -s 8972 192.168.1.20
# 8972 + 28 = 9000 — if this works, jumbo frames are working

# Set CNI MTU accordingly (subtract overlay overhead)
# VXLAN on 9000 MTU: 9000 - 50 = 8950
# Native routing on 9000 MTU: 9000 (no overhead)
```

Switch configuration: enable jumbo frames globally:
```
# Cisco NX-OS
policy-map type network-qos jumbo
  class type network-qos class-default
    mtu 9216
system qos
  service-policy type network-qos jumbo
```

---

## 5. Load Balancers on Bare Metal

Cloud Kubernetes gets cloud-native LBs for free. Bare metal needs an alternative.

### MetalLB
MetalLB implements LoadBalancer service type for bare metal using BGP or L2 (ARP/NDP).

```yaml
# MetalLB L2 mode (simple, no BGP required)
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production
  namespace: metallb-system
spec:
  addresses:
    - 192.168.100.100-192.168.100.200
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
```

```yaml
# MetalLB BGP mode (recommended for production)
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: tor-switch
  namespace: metallb-system
spec:
  myASN: 64512
  peerASN: 65000
  peerAddress: 192.168.1.1
---
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
    - production
```

### kube-vip
Alternative to MetalLB: uses VRRP/ARP for HA virtual IPs.

```yaml
# kube-vip as a DaemonSet for LoadBalancer services
# Configured via manifest with VRID and VIP range
env:
  - name: vip_leasename
    value: plndr-svcs-lock
  - name: lb_enable
    value: "true"
  - name: lb_port
    value: "80"
```

---

## 6. External DNS and IP Planning

Plan your IP ranges before deploying:

```
Physical Network:    192.168.0.0/16
  Node management:   192.168.1.0/24   (node SSH, kubelet API)
  LoadBalancer VIPs: 192.168.100.0/24 (MetalLB pool)

Kubernetes Internal:
  Pod CIDR:          10.244.0.0/16    (never routable externally)
  Service CIDR:      10.96.0.0/12     (never routable externally)
  Node CIDR mask:    /24              (256 pods per node max)
```

```bash
# Calculate how many nodes fit in a pod CIDR
# podCIDR=10.244.0.0/16, nodeMask=/24
# 2^(24-16) = 256 nodes × 254 usable IPs/node
```

---

## 7. Node Network Configuration at Scale

For consistent bare-metal node networking, use automation:

### Netplan (Ubuntu)
```yaml
# /etc/netplan/01-k8s-node.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      mtu: 9000
  bonds:
    bond0:
      interfaces: [eth0, eth1]
      mtu: 9000
      parameters:
        mode: 802.3ad
        lacp-rate: fast
        mii-monitor-interval: 100
      addresses: [192.168.1.10/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

### NMState (Red Hat / OpenShift)
```yaml
# NMState declarative network config
interfaces:
  - name: bond0
    type: bond
    state: up
    ipv4:
      address:
        - ip: 192.168.1.10
          prefix-length: 24
      enabled: true
    link-aggregation:
      mode: 802.3ad
      port:
        - eth0
        - eth1
```

---

## 8. RDMA and High-Performance Networking

For AI/ML workloads requiring InfiniBand or RoCE:

```bash
# Check RDMA devices
rdma dev

# Install RDMA CNI plugin
# Use Multus + RDMA device plugin for secondary interfaces with RDMA
kubectl get pods -n kube-system | grep rdma
```

---

## 9. Bare Metal Networking Checklist

Pre-deployment validation:

```bash
# 1. Confirm IP forwarding
sysctl net.ipv4.ip_forward   # must be 1

# 2. Check MTU consistency
for node in node1 node2 node3; do
  ssh $node ip link show eth0 | grep mtu
done

# 3. Verify no duplicate IPs
arping -D -I eth0 192.168.1.10

# 4. Check NIC bonding is active
cat /proc/net/bonding/bond0 | grep -E "Active|Speed"

# 5. Test inter-node bandwidth
# On node2: iperf3 -s
# On node1: iperf3 -c node2 -t 30 -P 4

# 6. Check VLAN tagging
tcpdump -i eth0 -n vlan

# 7. Verify BGP sessions (if using Calico/MetalLB)
calicoctl node status

# 8. Check DNS resolution
kubectl run -it --rm debug --image=nicolaka/netshoot -- nslookup kubernetes.default
```

---

## 10. Summary

| Component | Bare Metal Decision |
|-----------|-------------------|
| Topology | Spine-Leaf preferred for scale |
| NIC | LACP bond for redundancy, SR-IOV for performance |
| MTU | Jumbo frames (9000) end-to-end |
| Load Balancer | MetalLB (BGP mode) or kube-vip |
| IP planning | Separate physical, pod, service, and VIP ranges |
| Pod routing | Native (BGP) preferred; VXLAN for simpler setup |

---

## Online Resources

| Resource | Type | What you practice |
|----------|------|-------------------|
| [Killercoda Playground](https://killercoda.com/) | Free playground | Inspect bonding, bridge VLAN tables, and MetalLB on a real Linux node |
| [KodeKloud: Kubernetes Networking Deep Dive](https://www.kodekloud.com/learning-path/kubernetes) | Paid course (free trial) | Bare-metal load balancing and node network configuration labs |

---

**Next:** [Lesson 08 — Cloud Provider Networking Basics](08-cloud-provider-networking.md)
