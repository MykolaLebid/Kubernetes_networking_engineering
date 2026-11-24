# Platform Network Engineering

## Overview

Three books: K8s Networking (34 lessons) · CF Networking (20 lessons) · Migration Guide — plus 16 cheat sheets.

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

## Book 1: Kubernetes Networking — 34 Lessons

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

## Book 2: CF Networking — 20 Lessons

### Track CF-A — Platform Foundations

| # | Lesson | Topics |
|---|--------|--------|
| cf-01 | [Platform Architecture](lessons/cf-01-platform-architecture.md) | CF components, Diego, Garden, BBS, routing architecture overview |
| cf-02 | [Garden Container Networking](lessons/cf-02-garden-container-networking.md) | Garden-runC, container lifecycle, network setup hooks |
| cf-03 | [BOSH DNS](lessons/cf-03-bosh-dns.md) | BOSH DNS service discovery, aliases, health checks, Consul replacement |
| cf-04 | [IPAM](lessons/cf-04-ipam.md) | Subnet allocation, container IP assignment, Silk IPAM internals |

### Track CF-B — Overlay & Policy

| # | Lesson | Topics |
|---|--------|--------|
| cf-05 | [Silk CNI and VXLAN](lessons/cf-05-silk-cni-vxlan.md) | Silk CNI plugin, VXLAN overlay, VTEP setup, cross-cell traffic |
| cf-06 | [VXLAN Policy Agent](lessons/cf-06-vxlan-policy-agent.md) | Policy enforcement via iptables, container-to-container policy rules |
| cf-07 | [Application Security Groups](lessons/cf-07-application-security-groups.md) | ASG egress rules, staging vs running ASGs, platform defaults |
| cf-08 | [Garden Namespaces](lessons/cf-08-garden-namespaces.md) | Linux namespace isolation, user namespaces, rootless containers |

### Track CF-C — Routing Layer

| # | Lesson | Topics |
|---|--------|--------|
| cf-09 | [Gorouter](lessons/cf-09-gorouter.md) | HTTP/WebSocket routing, route table, sticky sessions, TLS termination |
| cf-10 | [TCP Router](lessons/cf-10-tcp-router.md) | TCP routing tier, port allocation, HAProxy integration |
| cf-11 | [Routes and Domains](lessons/cf-11-routes-domains.md) | Shared/private domains, route mapping, blue-green routing patterns |
| cf-12 | [Service Discovery](lessons/cf-12-service-discovery.md) | Internal routes, `apps.internal` domain, container-to-container DNS |

### Track CF-D — Security & Isolation

| # | Lesson | Topics |
|---|--------|--------|
| cf-13 | [Container-to-Container Network Policies](lessons/cf-13-c2c-network-policies.md) | C2C policy API, Silk policy enforcement, allow-list model |
| cf-14 | [TLS Certificates](lessons/cf-14-tls-certificates.md) | CredHub, certificate rotation, mTLS between platform components |
| cf-15 | [Org and Space Isolation](lessons/cf-15-org-space-isolation.md) | Multi-tenancy model, isolation segments, dedicated routers and cells |

### Track CF-E — Observability

| # | Lesson | Topics |
|---|--------|--------|
| cf-16 | [Observability](lessons/cf-16-observability.md) | Loggregator, metrics-discovery, network flow visibility |
| cf-17 | [Logging and Metrics](lessons/cf-17-logging-metrics.md) | Log cache, syslog drains, Prometheus scraping, Grafana dashboards |

### Track CF-F — Korifi / CF on K8s

| # | Lesson | Topics |
|---|--------|--------|
| cf-18 | [Korifi](lessons/cf-18-korifi.md) | CF API on Kubernetes, Korifi controllers, kpack, networking CRDs |

### Track CF-G — Migration & Comparison

| # | Lesson | Topics |
|---|--------|--------|
| cf-19 | [CF-to-K8s Migration Patterns](lessons/cf-19-cf-to-k8s-migration-patterns.md) | Lift-and-shift, strangler fig, networking equivalence mapping |
| cf-20 | [CF vs K8s Comparison](lessons/cf-20-cf-vs-k8s-comparison.md) | Side-by-side: routing, networking, isolation, observability, ops model |

---

## Book 3: Migration Guide

| # | Chapter | Topics |
|---|---------|--------|
| mig-00 | [Migration Overview](lessons/mig-00-migration-overview.md) | Scope, goals, decision framework for CF-to-K8s migration |
| mig-01 | [Networking Equivalence Map](lessons/mig-01-networking-equivalence-map.md) | ASG → NetworkPolicy, Gorouter → Ingress/Gateway API, C2C → NetworkPolicy |
| mig-02 | [Migration Runbook](lessons/mig-02-migration-runbook.md) | Step-by-step runbook: DNS cutover, traffic shifting, rollback procedure |
| mig-03 | [Hybrid CF + K8s Operations](lessons/mig-03-hybrid-cf-k8s-operations.md) | Running CF and K8s in parallel, shared observability, joint on-call |

---

## Cheat Sheets

| # | Cheat Sheet | Topics |
|---|-------------|--------|
| cs-00 | [Linux Networking Quick Reference](cheatsheets/cs-00-linux-networking.md) | ip, ss, netns, veth, bridge, tc commands |
| cs-01 | [iptables / nftables](cheatsheets/cs-01-iptables-nftables.md) | Chains, tables, common rules, conntrack |
| cs-02 | [eBPF and BPF Tools](cheatsheets/cs-02-ebpf-bpftools.md) | bpftool, bpftrace, XDP programs, map inspection |
| cs-03 | [CNI Plugins Comparison](cheatsheets/cs-03-cni-comparison.md) | Flannel, Calico, Cilium, Weave — feature matrix |
| cs-04 | [Kubernetes Services](cheatsheets/cs-04-k8s-services.md) | ClusterIP, NodePort, LB, ExternalName, headless |
| cs-05 | [Network Policy Patterns](cheatsheets/cs-05-network-policy-patterns.md) | Default-deny, namespace isolation, egress FQDN |
| cs-06 | [Ingress and Gateway API](cheatsheets/cs-06-ingress-gateway-api.md) | Ingress rules, GatewayClass, HTTPRoute, TCPRoute |
| cs-07 | [CoreDNS](cheatsheets/cs-07-coredns.md) | Corefile syntax, plugins, ndots, NodeLocal DNSCache |
| cs-08 | [Istio / Service Mesh](cheatsheets/cs-08-istio-service-mesh.md) | VirtualService, DestinationRule, PeerAuthentication, ambient |
| cs-09 | [AWS EKS Networking](cheatsheets/cs-09-aws-eks-networking.md) | VPC CNI, ENI limits, NLB/ALB annotations, IRSA |
| cs-10 | [OpenShift Networking](cheatsheets/cs-10-openshift-networking.md) | OVN-K, Routes, EgressIP, EgressFirewall |
| cs-11 | [CF Networking](cheatsheets/cs-11-cf-networking.md) | Gorouter, Silk, ASGs, C2C policy, BOSH DNS |
| cs-12 | [CF vs K8s Networking](cheatsheets/cs-12-cf-vs-k8s-networking.md) | Side-by-side equivalence table |
| cs-13 | [Observability Tools](cheatsheets/cs-13-observability-tools.md) | Hubble, tcpdump, netshoot, conntrack, Loggregator |
| cs-14 | [AI / GPU Cluster Networking](cheatsheets/cs-14-ai-gpu-networking.md) | RDMA, SR-IOV, Multus, RoCE, rail topology, EFA |
| cs-15 | [Troubleshooting Runbook](cheatsheets/cs-15-troubleshooting-runbook.md) | L1→L7→K8s→CNI methodology, common failure patterns |

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

Phase 9 — CF Networking (cf-01–cf-20)
  Platform architecture → Garden/Silk → Gorouter → ASGs → C2C → Korifi → Migration

Phase 10 — Migration & Cheat Sheets
  CF-to-K8s migration patterns → Hybrid ops → 16 quick-reference cheat sheets
```

---

## Key Ordering Rationale

| Decision | Why |
|----------|-----|
| eBPF (10) before Calico (11) and Cilium (12) | Cilium is built on eBPF — readers need the primitives first |
| IPv6 (15) after DNS (14), before Network Policy (16) | IPv6 is a CNI/Service configuration concern, not an "advanced" topic |
| ArgoCD (33) as GitOps track | Network engineers manage multi-cluster configs via GitOps; sync waves are critical for CNI→policy→app ordering |
| AI Networking (34) as final lesson | Requires all earlier concepts: SR-IOV (CNI), RDMA (bare metal), Multus (CNI spec), eBPF (observability) |
| CF Networking after K8s book | CF concepts build on the networking primitives (VXLAN, namespaces, iptables) covered in the K8s book |
| Migration Guide after both books | Requires fluency in both CF and K8s networking models |

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
| cf-05 | Silk VXLAN overlay — container to VTEP to cell |
| cf-09 | Gorouter route table lookup + TLS termination flow |
| cf-13 | C2C policy enforcement via iptables on Garden cells |

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

### 15. CF Networking
- Garden container networking and Silk CNI
- VXLAN overlay with VTEP-per-cell model
- Gorouter and TCP Router for HTTP and TCP ingress
- Application Security Groups (ASG) for egress control
- Container-to-container (C2C) policy with iptables enforcement
- BOSH DNS for service discovery within the platform
- Org/space isolation and isolation segments
- Korifi: CF API layer on top of Kubernetes

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
| `cf` CLI | Cloud Foundry application management |
| `bosh` CLI | BOSH deployment and VM management |
| `korifi` CLI | CF API on Kubernetes |

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
- [CF Silk CNI](https://github.com/cloudfoundry/silk)
- [CF Networking Release](https://github.com/cloudfoundry/cf-networking-release)
- [Korifi](https://github.com/cloudfoundry/korifi)
