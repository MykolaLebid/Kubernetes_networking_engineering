# Kubernetes Network Engineering

## Overview

Kubernetes Network Engineering covers the design, implementation, and operation of networking within and around Kubernetes clusters. It bridges traditional network engineering with cloud-native infrastructure, requiring knowledge of CNI plugins, service meshes, and the underlying Linux networking primitives that power them — from bare metal spine-leaf fabrics to AI GPU clusters.

> **Free learning resources mapped to every lesson:** [RESOURCES.md](RESOURCES.md)

---

## Practice Environment

Every lesson uses **two terminals**:

```bash
# Terminal 1 — Linux node (Linux kernel commands)
minikube ssh

# Terminal 2 — Mac (kubectl + ip addr/route)
kubectl get pods -A
ip addr   # iproute2mac wrapper
```

Linux-only commands (`ip netns`, `ip link add veth`, `iptables`) run in `minikube ssh`.  
Cluster commands (`kubectl`, `calicoctl`, `cilium`) run from your Mac terminal.

---

## Course: 35 Lessons

### Track A — Linux & Bare Metal Foundations

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 01 | [Linux Networking Fundamentals](lessons/01-linux-networking-fundamentals.md) | `minikube ssh` | namespaces, veth pairs, bridges, ip_forward |
| 02 | [IP Routing and Forwarding](lessons/02-ip-routing-and-forwarding.md) | `minikube ssh` + `ip route` | routing tables, policy routing, ECMP |
| 03 | [iptables and Netfilter](lessons/03-iptables-and-netfilter.md) | `minikube ssh` | chains, tables, conntrack, IPVS, kube-proxy rules |
| 04 | [Network Namespaces Deep Dive](lessons/04-network-namespaces-deep-dive.md) | `minikube ssh` | lifecycle, CNI sequence, nsenter, pause container |
| 05 | [VXLAN and Overlay Networks](lessons/05-vxlan-and-overlay-networks.md) | `minikube ssh` | VXLAN, Geneve, FDB, MTU, Flannel overlay |
| 06 | [BGP Fundamentals](lessons/06-bgp-fundamentals.md) | `minikube ssh` + `kubectl` | BGP topology, Route Reflector, eBGP with ToR, BFD |
| 07 | [Bare Metal Network Infrastructure](lessons/07-bare-metal-network-infrastructure.md) | `minikube ssh` | Spine-Leaf, bonding, VLAN design, jumbo frames |

### Track B — CNI Plugins & eBPF

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 08 | [Cloud Provider Networking Basics](lessons/08-cloud-provider-networking.md) | `kubectl` | AWS VPC CNI, GKE Alias IPs, AKS Azure CNI |
| 09 | [CNI Specification and Plugin Architecture](lessons/09-cni-specification.md) | `minikube ssh` + `kubectl` | CNI spec, ADD/DEL, IPAM plugins, Multus |
| 10 | [eBPF and XDP](lessons/10-ebpf-xdp.md) | `minikube ssh` + `bpftool` | XDP, TC hooks, BPF maps, Tetragon, bpftool |
| 11 | [Calico CNI Deep Dive](lessons/11-calico-cni-deep-dive.md) | `kubectl` + `calicoctl` | Felix, BIRD, BGP, IPAM blocks, eBPF dataplane |
| 12 | [Cilium CNI and eBPF Dataplane](lessons/12-cilium-cni-ebpf.md) | `kubectl` + `cilium` | eBPF identity policy, kube-proxy replacement, Hubble |

### Track C — Kubernetes Networking Layer

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 13 | [Kubernetes Services and kube-proxy](lessons/13-kubernetes-services-kube-proxy.md) | `kubectl` + `minikube ssh` | ClusterIP, NodePort, LB, EndpointSlices, IPVS |
| 14 | [CoreDNS and Service Discovery](lessons/14-coredns-service-discovery.md) | `kubectl` | Corefile, ndots:5, NodeLocal DNSCache, stub zones |
| 15 | [IPv6 and Dual-Stack Kubernetes](lessons/15-ipv6-dual-stack.md) | `kubectl` | dual-stack setup, ipFamilyPolicy, NDP, cloud support |
| 16 | [Network Policies: Microsegmentation](lessons/16-network-policies.md) | `kubectl` | default-deny, selectors, L7 policy, FQDN egress |

### Track D — Ingress and Load Balancing

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 17 | [Ingress Controllers and L7 Load Balancing](lessons/17-ingress-controllers.md) | `kubectl` + `minikube tunnel` | NGINX, Traefik, TLS, cert-manager |
| 18 | [Gateway API: Next-Generation Ingress](lessons/18-gateway-api.md) | `kubectl` | GatewayClass, HTTPRoute, TCPRoute, GRPCRoute |
| 19 | [MetalLB and kube-vip](lessons/19-metallb-kube-vip.md) | `kubectl` + `minikube` | L2 mode, BGP mode, shared IPs, kube-vip |
| 20 | [Cloud Provider Load Balancers](lessons/20-cloud-load-balancers.md) | `kubectl` + AWS/GCP/Azure CLI | AWS NLB/ALB, GKE LB, AKS Standard LB |

### Track E — Advanced Topics

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 21 | [Service Mesh with Istio](lessons/21-service-mesh-istio.md) | `kubectl` + `istioctl` | mTLS, AuthorizationPolicy, VirtualService, ambient mode |
| 22 | [Multi-Cluster Networking](lessons/22-multi-cluster-networking.md) | `kubectl` + `cilium` | Cluster Mesh, Istio multi-cluster, Submariner, MCS API |
| 23 | [Network Security Hardening](lessons/23-network-security-hardening.md) | `kubectl` | default-deny, metadata block, encryption, FQDN policy |
| 24 | [Network Observability and Troubleshooting](lessons/24-network-observability-troubleshooting.md) | `kubectl` + `hubble` + `minikube ssh` | Hubble, packet capture, latency, DNS debug |

### Track F — OpenShift Networking

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 25 | [OpenShift Networking Overview](lessons/25-openshift-networking-overview.md) | `oc` | CNO, OVN-Kubernetes, namespace isolation, default CIDRs |
| 26 | [OVN-Kubernetes: OpenShift's Default CNI](lessons/26-ovn-kubernetes.md) | `oc` + `ovs-vsctl` | OVS, ACLs, Geneve tunnels, IPsec |
| 27 | [OpenShift Routes and HAProxy Router](lessons/27-openshift-routes-haproxy.md) | `oc` | Route CRD, edge/passthrough/reencrypt, A/B routing |
| 28 | [OpenShift EgressIP and EgressFirewall](lessons/28-openshift-egress.md) | `oc` | EgressIP, EgressFirewall, DNS-based egress rules |

### Track G — AWS Networking

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 29 | [AWS EKS Networking Deep Dive](lessons/29-aws-eks-networking.md) | `kubectl` + `aws` CLI | VPC CNI, ENI limits, prefix delegation, Security Groups for Pods |
| 30 | [AWS VPC Design for Kubernetes](lessons/30-aws-vpc-design.md) | `aws` CLI | VPC sizing, subnet tags, ENIConfig, VPC endpoints |
| 31 | [AWS Load Balancer Controller Deep Dive](lessons/31-aws-load-balancer-controller.md) | `kubectl` + `aws` CLI | NLB, ALB, IngressGroup, weighted routing, IRSA |
| 32 | [AWS Hybrid and Multi-Cluster Networking](lessons/32-aws-hybrid-multicluster.md) | `kubectl` + `aws` CLI | VPC peering, Transit Gateway, Direct Connect, EKS Anywhere |

### Track H — GitOps & Delivery

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 33 | [ArgoCD and GitOps for Network Configuration](lessons/33-argocd-gitops.md) | `kubectl` + `argocd` CLI | App CRD, sync waves, multi-cluster deploy, NetworkPolicy drift |

### Track I — AI Platform Networking

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 34 | [AI Platform Networking on Kubernetes](lessons/34-ai-platform-networking.md) | `kubectl` + `bpftool` | RDMA, SR-IOV, Multus, InfiniBand, RoCE, GPU Operator, rail topology |

---

## Learning Path

```
Phase 1 — Linux Foundations (Lessons 01–07)
  Kernel primitives → veth → iptables → namespaces → VXLAN → BGP → bare metal

Phase 2 — CNI & eBPF (Lessons 08–12)
  Cloud networking models → CNI spec → eBPF fundamentals → Calico → Cilium

Phase 3 — Kubernetes Networking (Lessons 13–16)
  Services → DNS → IPv6/dual-stack → Network Policy

Phase 4 — Ingress & Load Balancing (Lessons 17–20)
  NGINX/Traefik → Gateway API → MetalLB → Cloud LBs

Phase 5 — Advanced (Lessons 21–24)
  Istio → Multi-cluster → Security → Observability

Phase 6 — OpenShift (Lessons 25–28)
  OVN-Kubernetes → Routes → EgressIP → EgressFirewall

Phase 7 — AWS (Lessons 29–32)
  EKS networking → VPC design → LB Controller → Hybrid

Phase 8 — GitOps & AI (Lessons 33–34)
  ArgoCD sync waves → AI cluster networking (RDMA, SR-IOV, rail topology)
```

---

## Key Ordering Rationale

| Decision | Why |
|----------|-----|
| eBPF (10) before Calico (11) and Cilium (12) | Cilium is built on eBPF — readers need the primitives first |
| IPv6 (15) after DNS (14), before Network Policy (16) | IPv6 is a CNI/Service configuration concern, not an "advanced" topic |
| ArgoCD (33) as GitOps track | Network engineers manage multi-cluster configs via GitOps; sync waves are critical for CNI→policy→app ordering |
| AI Networking (34) as final lesson | Requires all earlier concepts: SR-IOV (CNI), RDMA (bare metal), Multus (CNI spec), eBPF (observability) |

---

## ASCII Diagrams Reference

Lessons with detailed network diagrams:

| Lesson | Diagrams |
|--------|---------|
| 01 | veth pair + bridge topology |
| 03 | Netfilter 5-hook packet traversal |
| 05 | VXLAN header encapsulation |
| 06 | BGP full-mesh vs Route Reflector |
| 10 | eBPF XDP/TC hook positions on network stack |
| 12 | Cilium identity-based policy flow |
| 13 | iptables DNAT chain (KUBE-SERVICES→KUBE-SVC→KUBE-SEP) |
| 14 | ndots:5 DNS search path (6-query sequence) |
| 15 | Dual-stack address assignment + NDP vs ARP |
| 21 | Sidecar injection + mTLS SPIFFE handshake |
| 25 | CNO → OVN-Kubernetes component architecture |
| 29 | ENI secondary IP assignment model |
| 32 | Transit Gateway hub-and-spoke vs VPC peering |
| 33 | ArgoCD component architecture + sync wave ordering |
| 34 | Rail-optimized GPU cluster topology |

---

## Core Topics

### 1. Kubernetes Networking Fundamentals
- The Kubernetes networking model: every pod gets its own IP, all pods can communicate without NAT
- Pod-to-pod communication within a node (veth pairs, Linux bridges)
- Pod-to-pod communication across nodes (overlay vs underlay networks)
- Node networking and cluster CIDRs (`podCIDR`, `serviceCIDR`, `clusterCIDR`)

### 2. Container Network Interface (CNI)
- What CNI is and how the kubelet invokes it
- Popular CNI plugins and their trade-offs:
  - **Flannel** — simple VXLAN overlay, good for learning
  - **Calico** — BGP-based, supports NetworkPolicy, high performance
  - **Cilium** — eBPF-powered, deep observability, Hubble integration
  - **Multus** — meta-CNI for attaching multiple network interfaces to pods
- IPAM (IP Address Management) strategies

### 3. Kubernetes Services & kube-proxy
- ClusterIP, NodePort, LoadBalancer, ExternalName service types
- How kube-proxy programs iptables / IPVS rules
- Endpoints and EndpointSlices
- DNS-based service discovery with CoreDNS
- Headless services and stateful workloads

### 4. Network Policies
- Ingress and egress policy rules
- Label selectors and namespace selectors
- Default-deny patterns and policy layering
- CNI plugin support matrix for NetworkPolicy enforcement

### 5. Ingress & Gateway API
- Ingress controllers (NGINX, Traefik, Envoy-based)
- TLS termination and certificate management (cert-manager)
- Gateway API: Gateway, HTTPRoute, TCPRoute, GRPCRoute
- Path-based and host-based routing

### 6. Service Mesh
- Sidecar proxy model (Istio / Envoy)
- mTLS between services, SPIFFE certificate rotation
- Traffic management: retries, timeouts, circuit breaking, canary
- Ambient mesh (sidecar-less Istio)

### 7. eBPF in Kubernetes Networking
- How Cilium uses eBPF to bypass iptables
- XDP (eXpress Data Path) for high-performance packet processing
- BPF maps and tail calls
- Hubble for flow-level observability
- Tetragon for security enforcement

### 8. Load Balancing & External Traffic
- MetalLB for bare-metal LoadBalancer services (L2 ARP + BGP ECMP)
- Cloud provider load balancer integrations (AWS NLB/ALB, GCP, Azure)
- ExternalTrafficPolicy: Local vs Cluster
- Source IP preservation

### 9. DNS in Kubernetes
- CoreDNS architecture and configuration
- Search domains, ndots:5, and FQDN resolution
- NodeLocal DNSCache (169.254.20.10)
- DNS performance tuning

### 10. Network Observability & Troubleshooting
- Systematic methodology: L1→L7→K8s→CNI
- Cilium Hubble UI and CLI for flow inspection
- Tools: `kubectl exec`, `tcpdump`, `netshoot`, `ss`, `ip`, `conntrack`
- Common issues: MTU mismatches, hairpin NAT, kube-dns flapping

### 11. IPv6 & Dual-Stack
- Enabling dual-stack clusters (podCIDR + serviceCIDR pairs)
- ipFamilyPolicy: SingleStack / PreferDualStack / RequireDualStack
- NDP (Neighbor Discovery Protocol) vs ARP

### 12. Multi-Cluster & Hybrid Networking
- Cilium Cluster Mesh (shared service discovery)
- Istio multi-cluster (primary-remote, multi-primary)
- Submariner for cross-cluster pod connectivity
- AWS Transit Gateway, Direct Connect, VPC Lattice

### 13. OpenShift-Specific Networking
- Cluster Network Operator (CNO) managing OVN-Kubernetes
- Route CRD: edge / passthrough / reencrypt TLS termination
- EgressIP with HA failover
- EgressFirewall with DNS-based rules

### 14. AI Platform Networking
- Rail-optimized spine-leaf topology for GPU clusters
- RDMA (Remote Direct Memory Access) — zero-copy, zero-CPU
- SR-IOV: hardware NIC partitioning for near-bare-metal pod performance
- Multus: dual-NIC pods (management eth0 + RDMA net1)
- NVIDIA GPU Operator + Network Operator
- NCCL AllReduce tuning; PFC + ECN for lossless RoCE
- AWS EFA for P4d/P5 EKS clusters

---

## Key Tools & Projects

| Tool | Purpose |
|------|---------|
| `cilium` CLI | Cilium management and status |
| `hubble` CLI | eBPF-based flow inspection |
| `calicoctl` | Calico resource management |
| `istioctl` | Istio installation and diagnosis |
| `netshoot` | Network troubleshooting container |
| `bpftool` | Inspect BPF programs and maps |
| `kubectl-trace` | Run bpftrace programs on nodes |
| `ksniff` | tcpdump via kubectl plugin |
| `goldpinger` | Pod connectivity health checker |
| `argocd` CLI | ArgoCD application management |
| `dcgm-exporter` | GPU metrics for Prometheus |

---

## Reference Standards & Specs

- [Kubernetes Networking Model](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [CNI Specification](https://github.com/containernetworking/cni/blob/main/SPEC.md)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [Network Policy API](https://network-policy-api.sigs.k8s.io/)
- [eBPF.io](https://ebpf.io/)
- [NVIDIA Network Operator](https://github.com/Mellanox/network-operator)
- [SR-IOV Network Operator](https://github.com/k8snetworkplumbingwg/sriov-network-operator)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
