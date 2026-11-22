# Lesson 25 — OpenShift Networking Overview

> **Track:** OpenShift Networking  
> **Prerequisites:** [Lesson 09 — CNI Specification](09-cni-specification.md), [Lesson 12 — Services](13-kubernetes-services-kube-proxy.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — OpenShift CLI (oc)
oc get network.operator cluster -o yaml | grep -A10 defaultNetwork
oc get pods -n openshift-network-operator
oc get clusternetwork 2>/dev/null

# Terminal 2 — oc
oc get pods -n openshift-ovn-kubernetes | head -10
oc get hostsubnet 2>/dev/null || echo "OVN-Kubernetes mode (no hostsubnet)"
```

---

## Why This Matters

OpenShift is Red Hat's enterprise Kubernetes distribution. Its networking stack differs from vanilla Kubernetes in important ways: it ships OVN-Kubernetes as its default CNI, uses a `Route` CRD instead of Ingress by default, enforces its own security model (SCCs), and adds concepts like EgressIP, EgressFirewall, and NetworkPolicy isolation by default. Understanding these differences lets you operate OpenShift clusters confidently.

```
OpenShift Cluster Network Operator (CNO) Architecture

  oc edit network.operator.openshift.io/cluster
              │
              ▼
  ┌───────────────────────────────────────────────────────────────┐
  │  Cluster Network Operator (CNO)                               │
  │  namespace: openshift-network-operator                        │
  │  Watches: network.operator.openshift.io/cluster              │
  │  Manages: OVN-Kubernetes (default) or OpenShift SDN          │
  └───────────────┬───────────────────────────────────────────────┘
                  │ creates/manages DaemonSets and Deployments
       ┌──────────┴───────────────────────────────────┐
       │                                              │
  ┌────▼────────────────────────────────┐  ┌──────────▼──────────────────┐
  │  OVN-Kubernetes DaemonSet           │  │  ovnkube-master Deployment  │
  │  ns: openshift-ovn-kubernetes       │  │  (control plane pods)       │
  │  ┌──────────────────────────────┐   │  │  ┌──────────────────────┐   │
  │  │ ovnkube-node (per node)      │   │  │  │ ovn-northd           │   │
  │  │ ├── ovs-vswitchd (OVS)       │   │  │  │ (NB DB → SB DB sync) │   │
  │  │ ├── ovsdb-server (br-int)    │   │  │  └──────────────────────┘   │
  │  │ └── ovn-controller           │   │  │  ┌──────────────────────┐   │
  │  └──────────────────────────────┘   │  │  │ NB DB (logical topo) │   │
  └─────────────────────────────────────┘  │  │ SB DB (physical flow)│   │
                                           │  └──────────────────────┘   │
                                           └─────────────────────────────┘

  Network.operator CR defaults:
    clusterNetwork:  10.128.0.0/14  (hostPrefix: 23 → 512 pods/node max)
    serviceNetwork:  172.30.0.0/16
    defaultNetwork:  OVNKubernetes (Geneve port 6081, MTU 1400)
```

---

## 1. OpenShift vs Vanilla Kubernetes Networking

| Feature | Vanilla Kubernetes | OpenShift |
|---------|-------------------|-----------|
| Default CNI | None (you choose) | OVN-Kubernetes |
| Ingress | Ingress API | Route CRD + HAProxy Router |
| NetworkPolicy | Optional | Enforced by default (namespace isolation) |
| Egress control | Via CNI | EgressIP, EgressFirewall CRDs |
| DNS | CoreDNS | CoreDNS (same) |
| Load Balancer | Cloud CCM / MetalLB | Same + MetalLB on bare metal |
| Security | PodSecurity Admission | Security Context Constraints (SCCs) |
| SDN history | N/A | OpenShift SDN (deprecated) → OVN-Kubernetes |

---

## 2. OpenShift Network Operator

OpenShift manages its network configuration through the **Cluster Network Operator (CNO)**. You never edit CNI configs directly — you edit the `Network.operator.openshift.io` custom resource.

```bash
# View current network configuration
oc get network.operator.openshift.io cluster -o yaml

# Key fields:
# spec.defaultNetwork.type: OVNKubernetes
# spec.clusterNetwork: pod CIDR
# spec.serviceNetwork: service CIDR
# spec.networkType: OVNKubernetes
```

```bash
# View the cluster-level network config (read-only summary)
oc get network.config.openshift.io cluster -o yaml
# status.clusterNetwork:
#   - cidr: 10.128.0.0/14
#     hostPrefix: 23          ← /23 per node = 512 pods max per node
# status.serviceNetwork:
#   - 172.30.0.0/16
# status.networkType: OVNKubernetes
```

---

## 3. Default Pod and Service CIDRs

OpenShift uses different default CIDRs from vanilla Kubernetes:

```
Pod CIDR:      10.128.0.0/14   (4 × /16 blocks)
Service CIDR:  172.30.0.0/16
Node prefix:   /23             (512 IPs per node)
```

Each node gets a `/23` from the pod CIDR:
```
Node 1: 10.128.0.0/23   (pods 10.128.0.1 – 10.128.1.254)
Node 2: 10.128.2.0/23
Node 3: 10.128.4.0/23
...
```

```bash
# See per-node pod CIDR allocations
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDRs}{"\n"}{end}'
```

---

## 4. Namespace Network Isolation

OpenShift enforces **namespace isolation by default** using NetworkPolicy. When you create a namespace, OpenShift automatically creates policies that:
- Allow traffic within the same namespace
- Deny traffic from other namespaces
- Allow ingress from the router namespace
- Allow ingress from the monitoring namespace

```bash
# View auto-created NetworkPolicies
oc get networkpolicy -n my-namespace
# NAME                                    POD-SELECTOR   AGE
# allow-from-openshift-ingress            <none>         5m
# allow-from-openshift-monitoring         <none>         5m
# allow-same-namespace                    <none>         5m
```

To allow traffic between namespaces:
```yaml
# Allow namespace B to receive from namespace A
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-namespace-a
  namespace: namespace-b
spec:
  podSelector: {}
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: namespace-a
```

---

## 5. OpenShift DNS

CoreDNS is used but configured via the DNS operator:

```bash
# View DNS operator config
oc get dns.operator.openshift.io default -o yaml

# Custom upstream DNS servers
oc edit dns.operator.openshift.io default
# spec:
#   servers:
#     - name: corporate-dns
#       zones:
#         - corp.example.com
#       forwardPlugin:
#         upstreams:
#           - 10.100.0.53
```

```bash
# DNS service (runs on each node via NodeLocal DNSCache)
oc get svc -n openshift-dns
# dns-default   ClusterIP   172.30.0.10   53/UDP,53/TCP

# NodeLocal cache address: 10.0.0.10 (or the node's local DNS cache)
```

---

## 6. OpenShift Monitoring Network

OpenShift's built-in monitoring stack (Prometheus, Alertmanager, Grafana) lives in `openshift-monitoring` and needs network access to scrape all pods.

```bash
# Check monitoring pods
oc get pods -n openshift-monitoring

# NetworkPolicy allows monitoring ingress automatically
oc get networkpolicy -A | grep monitoring
```

---

## 7. OpenShift SDN (Legacy — Deprecated)

Before OVN-Kubernetes, OpenShift used its own SDN plugin with three modes:

| Mode | Description |
|------|-------------|
| `subnet` | Flat network, no isolation between namespaces |
| `multitenant` | Per-namespace VXLAN VNI — full isolation |
| `networkpolicy` | NetworkPolicy API — selective isolation |

```bash
# Check if a cluster still uses OpenShift SDN (older clusters)
oc get network.operator.openshift.io cluster \
  -o jsonpath='{.spec.defaultNetwork.type}'
# OpenShiftSDN  ← legacy
# OVNKubernetes ← current
```

Migration from OpenShift SDN to OVN-Kubernetes is supported but requires a maintenance window.

---

## 8. Key OpenShift Networking CLI Commands

```bash
# Overall network status
oc get network.config.openshift.io cluster
oc get clusteroperator network

# CNO health
oc get pods -n openshift-network-operator
oc logs -n openshift-network-operator deploy/network-operator

# OVN-Kubernetes pods
oc get pods -n openshift-ovn-kubernetes

# Node network status
oc get pods -n openshift-network-diagnostics

# Run network connectivity checks
oc get podnetworkconnectivitycheck -n openshift-network-diagnostics | head -20
```

---

## 9. Summary

| Concept | OpenShift Detail |
|---------|-----------------|
| CNI | OVN-Kubernetes (default) |
| Config | Cluster Network Operator — never edit directly |
| Pod CIDR | 10.128.0.0/14, /23 per node |
| Service CIDR | 172.30.0.0/16 |
| Namespace isolation | Enforced by default via auto-created NetworkPolicy |
| Ingress | Route CRD + HAProxy (see Lesson 27) |
| Egress | EgressIP, EgressFirewall CRDs (see Lesson 28) |

---

**Next:** [Lesson 26 — OVN-Kubernetes: OpenShift's Default CNI](26-ovn-kubernetes.md)
