# Lesson 06 — BGP Fundamentals for Kubernetes

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 02 — IP Routing and Forwarding](02-ip-routing-and-forwarding.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — kubectl (Mac)
kubectl get pods -n calico-system   # check Calico/BIRD is running

# Terminal 2 — minikube node (Linux)
minikube ssh
# Check if BIRD is running (Calico BGP agent)
sudo ps aux | grep bird
ip route show proto bird   # routes installed by BGP
```

---

## Why This Matters

BGP (Border Gateway Protocol) is the routing protocol of the internet — and increasingly of enterprise data centers. Calico uses BGP to advertise pod routes without any overlay. Understanding BGP lets you integrate Kubernetes into existing network infrastructure, achieve wire-speed pod networking, and configure advanced traffic engineering on bare metal.

---

## 1. BGP Fundamentals

BGP is a **path-vector protocol**: routers advertise reachability to IP prefixes along with the path (list of AS numbers) used to reach them.

```
Key concepts:

AS (Autonomous System)   — a network under single administrative control, identified by ASN
ASN                      — 16-bit (1–65535) or 32-bit number; 64512–65534 = private ASNs
BGP Speaker              — a router running BGP
BGP Peer / Neighbor      — another BGP speaker you establish a session with
iBGP                     — BGP between peers in the SAME AS
eBGP                     — BGP between peers in DIFFERENT ASes
NLRI                     — Network Layer Reachability Information (the prefix being advertised)
```

---

## 2. BGP Session Establishment

BGP uses TCP port 179. Peers must be manually configured — BGP doesn't auto-discover neighbors.

```
State machine:
  Idle → Connect → Active → OpenSent → OpenConfirm → Established
```

```bash
# Check BGP session states with BIRD (used by Calico)
birdc show protocols
# Name       Proto      Table      State  Since         Info
# Node_192_168_1_20  BGP        ---        up     2024-01-15  Established

# Check with FRRouting (used in some bare-metal setups)
vtysh -c "show bgp summary"
```

---

## 3. How Calico Uses BGP

Calico runs a BGP agent (BIRD) on every node. Each node advertises the pod routes it owns.

```
Node A (ASN 64512) — podCIDR 10.244.0.0/24
Node B (ASN 64512) — podCIDR 10.244.1.0/24

Node A's BIRD advertises: 10.244.0.5/32 (each pod as a host route)
Node B receives this and installs: ip route add 10.244.0.5/32 via 192.168.1.10

No overlay needed — packets go directly at wire speed.
```

---

## 4. BGP Topologies in Kubernetes

### Full Mesh (default Calico)
Every node peers with every other node. Scales to ~50 nodes before becoming unwieldy.

```
Node1 ←→ Node2
Node1 ←→ Node3
Node2 ←→ Node3
  → n*(n-1)/2 sessions for n nodes
```

### Route Reflector (RR)
Dedicated RR nodes relay routes between peers. All nodes peer only with the RR.

```yaml
# Calico: designate a node as a Route Reflector
kubectl annotate node rr-node projectcalico.org/RouteReflectorClusterID=244.0.0.1
```

```bash
# In BGPPeer config, nodes peer with the RR only
cat <<EOF | kubectl apply -f -
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: peer-with-rr
spec:
  peerIP: 192.168.1.100   # RR IP
  asNumber: 64512
EOF
```

### eBGP with ToR (Top-of-Rack) Switches
Most scalable: each node peers with the physical switch using a unique ASN.

```
Node A (ASN 65001) peers with ToR (ASN 65000)
Node B (ASN 65002) peers with ToR (ASN 65000)
ToR redistributes routes between nodes
```

```yaml
apiVersion: projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  asNumber: 65001
  serviceLoadBalancerIPs:
    - cidr: 10.0.0.0/24   # advertise LB IPs to the ToR
```

---

## 5. BGP Path Attributes

Understanding these attributes is key for traffic engineering:

| Attribute | Use in Kubernetes |
|-----------|------------------|
| AS_PATH | Loop prevention; prefer shortest path |
| LOCAL_PREF | iBGP preference (higher = preferred) |
| MED (MULTI_EXIT_DISC) | Suggest preferred entry to external AS |
| NEXT_HOP | Next router to reach the prefix |
| COMMUNITY | Tag routes for policy (e.g., "don't advertise outside cluster") |

```bash
# View BGP routes with attributes in BIRD
birdc show route all
birdc show route for 10.244.0.5

# In FRRouting
vtysh -c "show bgp ipv4 unicast 10.244.0.5"
```

---

## 6. BGP Communities for Kubernetes

BGP communities are 32-bit tags attached to routes. Calico and MetalLB use them for policy.

```yaml
# MetalLB: advertise LoadBalancer IPs with a community tag
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: example
spec:
  communities:
    - my-community
---
apiVersion: metallb.io/v1beta1
kind: Community
metadata:
  name: my-community
spec:
  communities:
    - name: web-tier
      value: "64512:100"
```

Upstream router policy on the ToR:
```
If route has community 64512:100 → set LOCAL_PREF 200
```

---

## 7. BFD — Bidirectional Forwarding Detection

BFD provides subsecond failure detection for BGP sessions. Important for fast pod rerouting on bare metal.

```yaml
# Calico BGP peer with BFD
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: node-to-tor
spec:
  peerIP: 192.168.1.1
  asNumber: 65000
  bfdEnabled: true
```

Without BFD, BGP hold-timer default is 90 seconds — too slow for Kubernetes.

---

## 8. Advertising Service IPs via BGP

One powerful pattern on bare metal: advertise Service LoadBalancer or ExternalIP ranges via BGP so they're reachable from the rest of the network.

**Calico:**
```yaml
apiVersion: projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  serviceLoadBalancerIPs:
    - cidr: 10.100.0.0/24   # LB IP range
  serviceExternalIPs:
    - cidr: 10.200.0.0/24   # External IP range
  serviceClusterIPs:
    - cidr: 10.96.0.0/12    # cluster IP range (optional)
```

**MetalLB (BGP mode):**
```yaml
apiVersion: metallb.io/v1beta1
kind: BGPPeer
metadata:
  name: tor-switch
spec:
  myASN: 64512
  peerASN: 65000
  peerAddress: 192.168.1.1
```

---

## 9. Cloud Provider BGP Considerations

BGP is typically not available in public cloud VPCs — cloud providers abstract away routing via their SDN. However:

- **AWS Direct Connect / Transit Gateway**: BGP is used between on-prem and AWS. Kubernetes pod routes can be injected here via Calico or a transit VPC pattern.
- **GCP Cloud Router**: supports BGP for Dedicated Interconnect and VPN — not for internal pod routing in GKE.
- **Azure ExpressRoute**: BGP between on-prem and Azure. Azure CNI with BGP is possible in some hybrid scenarios.
- **Bare-metal in cloud (Equinix Metal, etc.)**: full BGP support — treat exactly like on-premises.

---

## 10. Troubleshooting BGP

```bash
# Is BIRD running on the node?
systemctl status bird
ps aux | grep bird

# Check BGP sessions
birdc show protocols all | grep -A5 BGP

# View all advertised/received routes
birdc show route
birdc show route import <protocol-name>
birdc show route export <protocol-name>

# Check if a specific pod route is being advertised
birdc show route for 10.244.0.5

# Calico-specific: check BGP status
calicoctl node status
# BGP Summary:
#   IP:192.168.1.10   AS:64512    peers   established/failed

# Check BGP peer connectivity
telnet 192.168.1.20 179
# If this fails → firewall blocking TCP/179

# TCPDUMP BGP traffic
tcpdump -i eth0 tcp port 179 -n

# Verify routes installed by BGP
ip route show | grep bird
# or look for routes with protocol bird
ip route show proto bird
```

---

## 11. Summary

| Concept | Kubernetes Application |
|---------|----------------------|
| BGP speaker | BIRD agent on each node (Calico) |
| iBGP full mesh | Default Calico (<50 nodes) |
| Route Reflector | Scalable Calico for 50+ nodes |
| eBGP with ToR | Enterprise bare-metal, wire-speed pod routing |
| BGP community | Traffic engineering, MetalLB policy |
| BFD | Fast failure detection (<1s) |
| Service advertisement | Make LB IPs routable from physical network |

---

## Online Resources

| Resource | Type | What you practice |
|----------|------|-------------------|
| [Killercoda Playground](https://killercoda.com/) | Free playground | Run Calico with BIRD; use `birdc show protocols` and `ip route show proto bird` on a real cluster |
| [KodeKloud: Kubernetes Networking Deep Dive](https://www.kodekloud.com/learning-path/kubernetes) | Paid course (free trial) | Covers BGP in the context of Calico CNI configuration |

---

**Next:** [Lesson 07 — Bare Metal Network Infrastructure for Kubernetes](07-bare-metal-network-infrastructure.md)
