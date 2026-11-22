# Lesson 01 — Linux Networking Fundamentals

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** Basic Linux command line familiarity  
> **Duration:** ~2 hours

---

## Practice Setup

All commands in this lesson run on **Linux**. Use two terminals side by side:

```bash
# Terminal 1 — minikube Linux node
minikube ssh

# Terminal 2 — your Mac (observe differences)
ip addr   # uses iproute2mac wrapper
```

Inside `minikube ssh` you have full Linux networking: `ip netns`, `ip link add veth`, `bridge`, `iptables`, etc.

---

## Why This Matters

Every Kubernetes networking component — CNI plugins, kube-proxy, service meshes — is built on Linux kernel networking primitives. Understanding these primitives lets you debug any higher-level abstraction by going one layer down.

---

## 1. The Linux Network Stack

```
Application (sockets)
       │
  Transport Layer (TCP/UDP)       ← kernel
       │
  Network Layer (IP)              ← kernel
       │
  Link Layer (Ethernet/drivers)   ← kernel + hardware
       │
  Physical (NIC / vNIC)
```

Kubernetes adds virtual layers (veth pairs, bridges, tunnels) between the Link and Network layers.

---

## 2. Network Namespaces

A **network namespace** gives a process its own isolated network stack: interfaces, routing table, iptables rules, and sockets.

```bash
# Create a namespace
ip netns add ns-blue

# List namespaces
ip netns list

# Run a command inside the namespace
ip netns exec ns-blue ip link list

# Delete
ip netns del ns-blue
```

Each Kubernetes **pod** runs in its own network namespace. The pause (infra) container holds the namespace; app containers join it via `--network=container:<id>`.

---

## 3. Virtual Ethernet Pairs (veth)

A **veth pair** is a bidirectional pipe between two network namespaces. Packets in one end come out the other.

```bash
# Create a veth pair
ip link add veth0 type veth peer name veth1

# Move veth1 into ns-blue
ip link set veth1 netns ns-blue

# Configure veth0 on the host
ip addr add 10.0.0.1/24 dev veth0
ip link set veth0 up

# Configure veth1 inside the namespace
ip netns exec ns-blue ip addr add 10.0.0.2/24 dev veth1
ip netns exec ns-blue ip link set veth1 up
ip netns exec ns-blue ip link set lo up

# Test connectivity
ping -c3 10.0.0.2
ip netns exec ns-blue ping -c3 10.0.0.1
```

This is exactly what a CNI plugin does when it creates a pod: one veth end goes into the pod namespace, the other stays on the host.

---

## 4. Linux Bridge

A **bridge** (layer 2 switch in software) connects multiple veth endpoints so pods on the same node can communicate.

```bash
# Create a bridge
ip link add br0 type bridge
ip link set br0 up
ip addr add 10.244.0.1/24 dev br0

# Attach veth0 (host side of pod veth pair) to the bridge
ip link set veth0 master br0
```

Flannel's `cbr0`, Docker's `docker0`, and Calico's `cali*` interfaces all follow this pattern.

---

## 5. Routing Table

Linux uses routing rules to decide where to send packets.

```bash
# Show main routing table
ip route show

# Add a route: reach 10.244.1.0/24 via 192.168.1.10
ip route add 10.244.1.0/24 via 192.168.1.10 dev eth0

# Add a host route for a pod IP
ip route add 10.244.0.5/32 dev veth_pod0

# Policy routing — multiple tables
ip rule list
ip route show table local
```

For cross-node pod routing, CNI plugins either:
- **Add static routes** per remote pod CIDR (Calico BGP, Flannel host-gw)
- **Encapsulate** packets in a tunnel and route the outer header (VXLAN, Geneve)

---

## 6. ARP and Neighbor Table

```bash
# Show ARP cache
ip neigh show

# Flush ARP for an interface
ip neigh flush dev eth0

# Static ARP entry
ip neigh add 10.244.0.5 lladdr aa:bb:cc:dd:ee:ff dev eth0
```

Calico uses `proxy_arp` on each veth so pods can reach any IP without an ARP for the gateway:

```bash
cat /proc/sys/net/ipv4/conf/cali1234abcd/proxy_arp
# 1
```

---

## 7. Key Kernel Parameters for Kubernetes

```bash
# IP forwarding — required so the node can route between pod and external traffic
sysctl net.ipv4.ip_forward=1
sysctl net.ipv6.conf.all.forwarding=1

# Allow iptables to see bridged traffic (needed by kube-proxy and many CNIs)
sysctl net.bridge.bridge-nf-call-iptables=1
sysctl net.bridge.bridge-nf-call-ip6tables=1

# Avoid conntrack table exhaustion
sysctl net.netfilter.nf_conntrack_max=1000000
```

These are set in `/etc/sysctl.d/99-kubernetes.conf` by kubeadm.

---

## 8. Hands-On Lab: Simulate a Two-Pod Node

Reproduce what a CNI plugin does on a single Linux machine.

```bash
# 1. Create two "pod" namespaces
ip netns add pod-a
ip netns add pod-b

# 2. Create a bridge to act as the node bridge
ip link add br0 type bridge
ip link set br0 up
ip addr add 10.244.0.1/24 dev br0

# 3. Create veth pairs and wire them up
ip link add veth-a type veth peer name veth-a-br
ip link add veth-b type veth peer name veth-b-br

ip link set veth-a netns pod-a
ip link set veth-b netns pod-b
ip link set veth-a-br master br0
ip link set veth-b-br master br0
ip link set veth-a-br up
ip link set veth-b-br up

# 4. Configure IPs inside pods
ip netns exec pod-a ip addr add 10.244.0.10/24 dev veth-a
ip netns exec pod-a ip link set veth-a up
ip netns exec pod-a ip link set lo up
ip netns exec pod-a ip route add default via 10.244.0.1

ip netns exec pod-b ip addr add 10.244.0.11/24 dev veth-b
ip netns exec pod-b ip link set veth-b up
ip netns exec pod-b ip link set lo up
ip netns exec pod-b ip route add default via 10.244.0.1

# 5. Test pod-a → pod-b
ip netns exec pod-a ping -c3 10.244.0.11

# 6. Cleanup
ip netns del pod-a
ip netns del pod-b
ip link del br0
```

---

## 9. Summary

| Primitive | Kubernetes Mapping |
|-----------|-------------------|
| Network namespace | Pod isolation boundary |
| veth pair | Pod ↔ node connection |
| Linux bridge | Intra-node pod switching |
| Routing table | Cross-node pod reachability |
| ip_forward sysctl | Node acts as a router |

---

## Further Reading

- `man ip-netns`, `man ip-link`, `man ip-route`
- [Linux Networking Explained — Julia Evans](https://jvns.ca/blog/2016/06/22/should-you-use-the-new-linux-network-namespaces/)
- Kernel docs: `Documentation/networking/net-namespaces.rst`

---

## Online Resources

| Resource | Type | What you practice |
|----------|------|-------------------|
| [iximiuz: Container Networking from Scratch](https://labs.iximiuz.com/tutorials/container-networking-from-scratch) | Free interactive lab | Build veth pairs, bridges, namespaces by hand in a real Linux environment — mirrors this lesson's lab exactly |
| [Killercoda Playground](https://killercoda.com/) | Free playground | Instant browser-based Linux node; run every `ip` command from this lesson without minikube |
| [iximiuz: Networking Challenges](https://labs.iximiuz.com/challenges) | Free challenges | Practical Linux networking problems with automated verification |

---

**Next:** [Lesson 02 — IP Routing and Forwarding in Linux](02-ip-routing-and-forwarding.md)
