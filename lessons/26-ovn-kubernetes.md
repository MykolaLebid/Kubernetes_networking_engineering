# Lesson 26 — OVN-Kubernetes: OpenShift's Default CNI

> **Track:** OpenShift Networking  
> **Prerequisites:** [Lesson 25 — OpenShift Networking Overview](25-openshift-networking-overview.md), [Lesson 03 — iptables](03-iptables-and-netfilter.md)  
> **Duration:** ~3 hours

---

## Practice Setup

```bash
# Terminal 1 — OpenShift node (via oc debug or oc rsh)
oc rsh -n openshift-ovn-kubernetes ds/ovnkube-node -- ovs-vsctl show
oc rsh -n openshift-ovn-kubernetes ds/ovnkube-node -- ovn-nbctl show 2>/dev/null | head -30

# Terminal 2 — oc CLI
oc get pods -n openshift-ovn-kubernetes
oc logs -n openshift-ovn-kubernetes ds/ovnkube-node -c ovnkube-node --tail=20
```

---

## Why This Matters

OVN-Kubernetes (Open Virtual Network for Kubernetes) is the default CNI for OpenShift 4.x and is increasingly used in vanilla Kubernetes. Unlike Calico or Cilium which bolt onto the kernel, OVN-Kubernetes builds a **virtual network using Open vSwitch (OVS)** — a software-defined networking stack that runs entirely in userspace and kernel, providing a full virtual topology with logical switches, routers, and load balancers.

---

## 1. Architecture

```
┌─────────────────────────────────────────────────────┐
│  OVN Northbound Database (logical network)          │
│  Logical Switches, Routers, Load Balancers, ACLs    │
└──────────────────┬──────────────────────────────────┘
                   │  ovn-northd translates
┌──────────────────▼──────────────────────────────────┐
│  OVN Southbound Database (physical network)         │
│  Chassis, Ports, Flows, BFD                         │
└──────────────────┬──────────────────────────────────┘
                   │  ovn-controller reads
┌──────────────────▼──────────────────────────────────┐
│  Open vSwitch (OVS) on each node                    │
│  Programs flow tables in the kernel                 │
└─────────────────────────────────────────────────────┘
```

**Components per node:**
- `ovn-controller` — reads Southbound DB, programs OVS flows
- `ovs-vswitchd` — OVS daemon implementing the dataplane
- `ovsdb-server` — OVS local database

**Components on control-plane nodes:**
- `ovn-northd` — translates logical network to physical
- `nbdb` — OVN Northbound database
- `sbdb` — OVN Southbound database

---

## 2. OVN-Kubernetes Pods in OpenShift

```bash
# View OVN-Kubernetes pods
oc get pods -n openshift-ovn-kubernetes -o wide

# On each node:
# ovnkube-node-xxxxx  (ovn-controller + ovs-vswitchd + ovsdb-server)

# On control-plane nodes additionally:
# ovnkube-master-xxxxx  (ovn-northd + nbdb + sbdb)

# Check health
oc get pods -n openshift-ovn-kubernetes | grep -v Running
```

---

## 3. The OVS Bridge

Each node has an OVS bridge (`br-int`) that connects all pods and handles all traffic:

```bash
# SSH into a node (OpenShift)
oc debug node/<node-name>
chroot /host

# View OVS bridges
ovs-vsctl show
# Bridge br-int
#   Port patch-br-int-to-breth0_<node>
#       Interface patch-br-int-to-breth0_<node>
#           type: patch
#   Port eeb73ac0d1e3789    ← pod veth port
#       Interface eeb73ac0d1e3789
#   Port k8s-<node>
#       Interface k8s-<node>

# List all OVS ports
ovs-vsctl list-ports br-int

# Show OVS flows (the actual packet processing rules)
ovs-ofctl dump-flows br-int | head -30
```

---

## 4. Logical Network Topology

OVN creates a virtual topology mirroring the Kubernetes topology:

```
Logical Switch (per namespace/node)
  └── Logical Switch Port (per pod)
         └── connected to
Logical Router (ovn_cluster_router)
  └── routes between all nodes and pods
         └── connected to
Logical Load Balancer (per Service)
  └── DNAT: ClusterIP → pod IPs
```

```bash
# View the OVN logical network (run on control-plane node)
oc exec -n openshift-ovn-kubernetes ovnkube-master-xxxxx -- \
  ovn-nbctl show | head -50

# View logical switches (one per node)
oc exec -n openshift-ovn-kubernetes ovnkube-master-xxxxx -- \
  ovn-nbctl ls-list

# View logical routers
oc exec -n openshift-ovn-kubernetes ovnkube-master-xxxxx -- \
  ovn-nbctl lr-list

# View load balancers (Services)
oc exec -n openshift-ovn-kubernetes ovnkube-master-xxxxx -- \
  ovn-nbctl lb-list | head -20
```

---

## 5. Pod Traffic Flow (Same Node)

```
Pod A (10.128.0.5) → Pod B (10.128.0.6)  [same node]

1. Pod A sends packet via veth to br-int OVS port
2. OVS flow table lookup:
   - Match: in_port=pod-a-port, ip.dst=10.128.0.6
   - Action: output to pod-b-port (direct, no routing needed)
3. Packet exits OVS to pod B's veth
```

---

## 6. Pod Traffic Flow (Cross Node)

```
Pod A (10.128.0.5, Node1) → Pod B (10.128.2.5, Node2)

1. Pod A → br-int (OVS)
2. OVS flow: route via ovn_cluster_router
3. OVN encapsulates in Geneve tunnel:
   - Outer IP: Node1 → Node2
   - Geneve header with tunnel key (VNI)
4. Packet exits Node1 via br-ex or tunnel interface
5. Node2 receives, OVS decapsulates
6. OVS flow: output to pod-b-port
```

```bash
# View tunnel interfaces on a node
ovs-vsctl list-ports br-int | grep tun
# or:
ip link show | grep genev   # Geneve tunnels
```

---

## 7. NetworkPolicy Implementation in OVN

OVN implements NetworkPolicy using **ACLs (Access Control Lists)** in the OVN Northbound database — not iptables.

```bash
# View ACLs (translated from NetworkPolicy)
oc exec -n openshift-ovn-kubernetes ovnkube-master-xxxxx -- \
  ovn-nbctl acl-list <logical-switch-name> | head -20

# Example ACL:
# from-lport  1000 (ip4 && ip4.src == 10.128.0.5) allow-related
# to-lport    1000 (ip4 && ip4.dst == 10.128.0.6 && tcp.dst == 80) allow
# to-lport    0    (ip4) drop   ← default deny
```

This is fundamentally different from Calico (iptables/eBPF) and Cilium (eBPF). ACLs are compiled into OVS flow tables by ovn-controller.

---

## 8. OVN-Kubernetes Modes

### Local Gateway Mode (default in OpenShift 4.10+)
Traffic from pods to external networks exits via the **local node's** interface. Preserves source IP for external traffic.

```bash
oc get network.operator.openshift.io cluster \
  -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.gatewayConfig}'
# routingViaHost: false (shared gateway)
# routingViaHost: true  (local gateway — recommended)
```

### Shared Gateway Mode (legacy)
All external traffic routes through the master nodes. Simpler but creates a bottleneck.

---

## 9. IPsec Encryption

OVN-Kubernetes supports transparent IPsec encryption between nodes.

```bash
# Enable IPsec (OpenShift)
oc patch network.operator.openshift.io cluster \
  --type=merge \
  -p '{"spec":{"defaultNetwork":{"ovnKubernetesConfig":{"ipsecConfig":{"mode":"Full"}}}}}'

# Check IPsec status
oc get pods -n openshift-ovn-kubernetes | grep ipsec
oc exec -n openshift-ovn-kubernetes ovnkube-node-xxxxx -- \
  ovs-vsctl get Open_vSwitch . other_config:certificate
```

---

## 10. Troubleshooting OVN-Kubernetes

```bash
# 1. Check OVN controller is in sync
oc exec -n openshift-ovn-kubernetes ovnkube-node-xxxxx -- \
  ovn-appctl -t ovn-controller connection-status

# 2. Check OVS flows for a pod
POD_IP=10.128.0.5
oc debug node/<node> -- chroot /host \
  ovs-ofctl dump-flows br-int | grep $POD_IP

# 3. Trace a packet through OVS
oc debug node/<node> -- chroot /host \
  ovs-appctl ofproto/trace br-int \
  "in_port=1,ip,ip_src=10.128.0.5,ip_dst=10.128.2.5,tcp,tcp_dst=80"

# 4. Check OVN Northbound DB is healthy
oc exec -n openshift-ovn-kubernetes ovnkube-master-xxxxx -- \
  ovn-nbctl show | wc -l

# 5. Check for stale ports
oc exec -n openshift-ovn-kubernetes ovnkube-master-xxxxx -- \
  ovn-nbctl lsp-list <switch> | grep -v "pod\|node"

# 6. Collect OVN logs
oc logs -n openshift-ovn-kubernetes ovnkube-node-xxxxx -c ovn-controller
oc logs -n openshift-ovn-kubernetes ovnkube-master-xxxxx -c northd

# 7. Run the network diagnostics operator
oc get podnetworkconnectivitycheck -n openshift-network-diagnostics \
  -o jsonpath='{range .items[?(@.status.failures)]}{.metadata.name}{"\n"}{end}'
```

---

## 11. OVN-Kubernetes vs Other CNIs

| Feature | OVN-Kubernetes | Calico | Cilium |
|---------|---------------|--------|--------|
| Dataplane | OVS flow tables | iptables/eBPF | eBPF |
| Policy engine | OVN ACLs | Felix (iptables/eBPF) | eBPF |
| Encapsulation | Geneve | VXLAN/IPIP/None | VXLAN/Geneve/None |
| Load balancing | OVN LB | iptables/eBPF | eBPF |
| Observability | OVS flows | Calico flow logs | Hubble |
| OpenShift default | Yes | Optional | Optional |

---

## 12. Summary

| Concept | Detail |
|---------|--------|
| Data plane | Open vSwitch (OVS) flow tables |
| Control plane | OVN (Northbound → Southbound → ovn-controller) |
| Encapsulation | Geneve tunnels between nodes |
| NetworkPolicy | Compiled to OVN ACLs (not iptables) |
| Services | OVN Logical Load Balancers |
| Encryption | IPsec transparent mode |
| Config | Via Cluster Network Operator — never directly |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) | Free 30-day cluster | The only free way to run `ovs-vsctl show`, inspect OVN NB/SB databases, and view Geneve tunnels in a real OpenShift cluster |
| [Red Hat Interactive Learning Portal](https://www.redhat.com/en/interactive-labs/openshift) | Free (Red Hat account) | Guided labs for OVN-Kubernetes network troubleshooting |

---

**Next:** [Lesson 27 — OpenShift Routes and HAProxy Router](27-openshift-routes-haproxy.md)
