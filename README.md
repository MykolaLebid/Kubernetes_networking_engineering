# Kubernetes Network Engineering

## Overview

Kubernetes Network Engineering covers the design, implementation, and operation of networking within and around Kubernetes clusters. It bridges traditional network engineering with cloud-native infrastructure, requiring knowledge of both CNI plugins, service meshes, and the underlying Linux networking primitives that power them.

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

## Course: 32 Lessons

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

### Track B — Cloud Provider Networking

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 08 | [Cloud Provider Networking Basics](lessons/08-cloud-provider-networking.md) | `kubectl` | AWS VPC CNI, GKE Alias IPs, AKS Azure CNI |

### Track C — CNI Plugins

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 09 | [CNI Specification and Plugin Architecture](lessons/09-cni-specification.md) | `minikube ssh` + `kubectl` | CNI spec, ADD/DEL, IPAM plugins, Multus |
| 10 | [Calico CNI Deep Dive](lessons/10-calico-cni-deep-dive.md) | `kubectl` + `calicoctl` | Felix, BIRD, BGP, IPAM blocks, eBPF dataplane |
| 11 | [Cilium CNI and eBPF Dataplane](lessons/11-cilium-cni-ebpf.md) | `kubectl` + `cilium` | eBPF, kube-proxy replacement, Hubble, Cluster Mesh |

### Track D — Kubernetes Networking Layer

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 12 | [Kubernetes Services and kube-proxy](lessons/12-kubernetes-services-kube-proxy.md) | `kubectl` + `minikube ssh` | ClusterIP, NodePort, LB, EndpointSlices, IPVS |
| 13 | [CoreDNS and Service Discovery](lessons/13-coredns-service-discovery.md) | `kubectl` | Corefile, ndots, NodeLocal DNSCache, stub zones |
| 14 | [Network Policies: Microsegmentation](lessons/14-network-policies.md) | `kubectl` | default-deny, selectors, L7 policy, FQDN egress |

### Track E — Ingress and Load Balancing

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 15 | [Ingress Controllers and L7 Load Balancing](lessons/15-ingress-controllers.md) | `kubectl` + `minikube tunnel` | NGINX, Traefik, TLS, cert-manager |
| 16 | [Gateway API: Next-Generation Ingress](lessons/16-gateway-api.md) | `kubectl` | GatewayClass, HTTPRoute, TCPRoute, GRPCRoute |
| 17 | [MetalLB and kube-vip](lessons/17-metallb-kube-vip.md) | `kubectl` + `minikube` | L2 mode, BGP mode, shared IPs, kube-vip |
| 18 | [Cloud Provider Load Balancers](lessons/18-cloud-load-balancers.md) | `kubectl` + AWS/GCP/Azure CLI | AWS NLB/ALB, GKE LB, AKS Standard LB |

### Track F — Advanced Topics

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 19 | [Service Mesh with Istio](lessons/19-service-mesh-istio.md) | `kubectl` + `istioctl` | mTLS, AuthorizationPolicy, VirtualService, ambient mode |
| 20 | [eBPF and XDP](lessons/20-ebpf-xdp.md) | `minikube ssh` + `bpftool` | XDP, TC hooks, BPF maps, Tetragon, bpftool |
| 21 | [IPv6 and Dual-Stack Kubernetes](lessons/21-ipv6-dual-stack.md) | `kubectl` | dual-stack setup, ipFamilyPolicy, NDP, cloud support |
| 22 | [Multi-Cluster Networking](lessons/22-multi-cluster-networking.md) | `kubectl` + `cilium` | Cluster Mesh, Istio multi-cluster, Submariner, MCS API |
| 23 | [Network Security Hardening](lessons/23-network-security-hardening.md) | `kubectl` | default-deny, metadata block, encryption, FQDN policy |
| 24 | [Network Observability and Troubleshooting](lessons/24-network-observability-troubleshooting.md) | `kubectl` + `hubble` + `minikube ssh` | Hubble, packet capture, latency, DNS debug |

### Track G — OpenShift Networking

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 25 | [OpenShift Networking Overview](lessons/25-openshift-networking-overview.md) | `oc` | CNO, OVN-Kubernetes, namespace isolation, default CIDRs |
| 26 | [OVN-Kubernetes: OpenShift's Default CNI](lessons/26-ovn-kubernetes.md) | `oc` + `ovs-vsctl` | OVS, ACLs, Geneve tunnels, IPsec |
| 27 | [OpenShift Routes and HAProxy Router](lessons/27-openshift-routes-haproxy.md) | `oc` | Route CRD, edge/passthrough/reencrypt, A/B routing |
| 28 | [OpenShift EgressIP and EgressFirewall](lessons/28-openshift-egress.md) | `oc` | EgressIP, EgressFirewall, DNS-based egress rules |

### Track H — AWS Networking

| # | Lesson | Practice | Topics |
|---|--------|----------|--------|
| 29 | [AWS EKS Networking Deep Dive](lessons/29-aws-eks-networking.md) | `kubectl` + `aws` CLI | VPC CNI, ENI limits, prefix delegation, Security Groups for Pods |
| 30 | [AWS VPC Design for Kubernetes](lessons/30-aws-vpc-design.md) | `aws` CLI | VPC sizing, subnet tags, ENIConfig, VPC endpoints |
| 31 | [AWS Load Balancer Controller Deep Dive](lessons/31-aws-load-balancer-controller.md) | `kubectl` + `aws` CLI | NLB, ALB, IngressGroup, weighted routing, IRSA |
| 32 | [AWS Hybrid and Multi-Cluster Networking](lessons/32-aws-hybrid-multicluster.md) | `kubectl` + `aws` CLI | VPC peering, Transit Gateway, Direct Connect, EKS Anywhere |

---

## Learning Path

```
Phase 1 — Linux Foundations (Lessons 01–07)
  Kernel primitives → veth → iptables → namespaces → VXLAN → BGP → bare metal

Phase 2 — Cloud & CNI (Lessons 08–11)
  Cloud networking models → CNI spec → Calico → Cilium

Phase 3 — Kubernetes Networking (Lessons 12–14)
  Services → DNS → Network Policy

Phase 4 — Ingress & Load Balancing (Lessons 15–18)
  NGINX/Traefik → Gateway API → MetalLB → Cloud LBs

Phase 5 — Advanced (Lessons 19–24)
  Istio → eBPF → IPv6 → Multi-cluster → Security → Observability

Phase 6 — OpenShift (Lessons 25–28)
  OVN-Kubernetes → Routes → EgressIP → EgressFirewall

Phase 7 — AWS (Lessons 29–32)
  EKS networking → VPC design → LB Controller → Hybrid
```

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
  - **Weave Net** — mesh overlay with built-in encryption
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
- Sidecar proxy model (Istio / Envoy, Linkerd / linkerd-proxy)
- mTLS between services, certificate rotation
- Traffic management: retries, timeouts, circuit breaking, canary
- Observability: distributed tracing, metrics, access logs
- Ambient mesh (sidecar-less Istio)

### 7. eBPF in Kubernetes Networking
- How Cilium uses eBPF to bypass iptables
- XDP (eXpress Data Path) for high-performance packet processing
- BPF maps and tail calls
- Hubble for flow-level observability
- Tetragon for security enforcement

### 8. Load Balancing & External Traffic
- MetalLB for bare-metal LoadBalancer services
- Cloud provider load balancer integrations (AWS NLB/ALB, GCP, Azure)
- ExternalTrafficPolicy: Local vs Cluster
- Source IP preservation

### 9. DNS in Kubernetes
- CoreDNS architecture and configuration
- Search domains and FQDN resolution
- Custom DNS entries and stub zones
- DNS performance tuning (ndots, dnsConfig)
- NodeLocal DNSCache

### 10. Network Observability & Troubleshooting
- Tools: `kubectl exec`, `tcpdump`, `netshoot`, `nmap`, `ss`, `ip`
- Cilium Hubble UI and CLI for flow inspection
- Network policy verification with `network-policy-api` conformance tests
- Tracing packet drops: conntrack, iptables LOG targets, kube-proxy logs
- Common issues: MTU mismatches, hairpin NAT, kube-dns flapping

### 11. IPv6 & Dual-Stack
- Enabling IPv6 single-stack or dual-stack clusters
- Pod and service CIDR planning for dual-stack
- CNI dual-stack support considerations

### 12. Multi-Cluster & Hybrid Networking
- Cluster Federation and Multi-Cluster Services (MCS API)
- Istio multi-cluster (primary-remote, multi-primary)
- Submariner for cross-cluster pod connectivity
- Connecting on-prem clusters to cloud via VPN or Direct Connect

### 13. Security Considerations
- mTLS everywhere with service mesh
- Network segmentation with NetworkPolicy
- Pod security (securityContext, hostNetwork risks)
- Egress filtering and FQDN-based policies (Cilium, Calico EE)
- Encryption in transit: WireGuard (Cilium/Calico), IPSec

---

## Learning Path

```
Phase 1 — Foundations
  └── Linux networking (namespaces, veth, iptables, routing)
  └── Container networking basics (Docker bridge, host, overlay)
  └── Kubernetes architecture overview

Phase 2 — Core Kubernetes Networking
  └── CNI deep dive (Calico or Cilium recommended)
  └── Services, DNS, kube-proxy
  └── NetworkPolicy authoring and testing

Phase 3 — Advanced Topics
  └── Ingress / Gateway API
  └── Service mesh (Istio or Linkerd)
  └── eBPF and Cilium

Phase 4 — Operations & Production
  └── Observability with Hubble / Prometheus / Jaeger
  └── Multi-cluster networking
  └── Security hardening and compliance
```

---

## Key Tools & Projects

| Tool | Purpose |
|------|---------|
| `cilium` CLI | Cilium management and status |
| `hubble` CLI | eBPF-based flow inspection |
| `calicoctl` | Calico resource management |
| `istioctl` | Istio installation and diagnosis |
| `linkerd` CLI | Linkerd mesh management |
| `netshoot` | Network troubleshooting container |
| `kubectl-trace` | Run bpftrace programs on nodes |
| `ksniff` | tcpdump via kubectl plugin |
| `goldpinger` | Pod connectivity health checker |

---

## Reference Standards & Specs

- [Kubernetes Networking Model](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [CNI Specification](https://github.com/containernetworking/cni/blob/main/SPEC.md)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [Network Policy API](https://network-policy-api.sigs.k8s.io/)
- [eBPF.io](https://ebpf.io/)
