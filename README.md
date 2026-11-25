# Platform Network Engineering

> **Live site:** https://mykolalibid.github.io/Kubernetes_networking_engineering/

Two complete courses + cert prep guides + cheat sheets, covering Kubernetes and Cloud Foundry networking from Linux primitives to AI GPU clusters, compliance frameworks, and industrial edge.

---

## What's inside

| Course | Lessons | Tracks |
|--------|---------|--------|
| **K8s Networking** | 41 lessons (00–40) | A–J |
| **CF Networking** | 23 lessons (cf-00–cf-22) | CF-A–CF-H |
| **Cheat sheets** | 16 | K8s vs CF side-by-side, eBPF, AWS, OpenShift, AI/GPU |
| **Migration guide** | 4 chapters | CF→K8s strategy, translation cookbook, coexistence |

**Cert prep:** [CKNE + CCA](docs/ckne-prep.md) · [CKA + CKS](docs/cka-cks-prep.md) · [Sector learning paths](docs/compliance-paths.md) (medtech/banking/manufacturing/big tech, CH/DE/USA)

---

## Practice environment

Every lesson uses two terminals:

```bash
# Terminal 1 — Linux node
minikube ssh

# Terminal 2 — Mac
kubectl get pods -A
```

Linux-only commands (`ip netns`, `ip link`, `iptables`, `bpftool`) run inside `minikube ssh`.  
Cluster commands (`kubectl`, `cilium`, `calicoctl`, `istioctl`) run from your Mac.

Validation scripts for each track are in `labs/` — run after completing a track to verify your setup.

---

## K8s Networking — 41 lessons

### Track A — Linux Foundations

| # | Lesson | Topics |
|---|--------|--------|
| 01 | [Linux Networking Fundamentals](lessons/01-linux-networking-fundamentals.md) | namespaces, veth pairs, bridges, ip_forward |
| 02 | [IP Routing and Forwarding](lessons/02-ip-routing-and-forwarding.md) | routing tables, policy routing, ECMP |
| 03 | [iptables and Netfilter](lessons/03-iptables-and-netfilter.md) | chains, tables, conntrack, IPVS, kube-proxy rules |
| 04 | [Network Namespaces Deep Dive](lessons/04-network-namespaces-deep-dive.md) | lifecycle, CNI sequence, nsenter, pause container |
| 05 | [VXLAN and Overlay Networks](lessons/05-vxlan-and-overlay-networks.md) | VXLAN, Geneve, FDB, MTU, Flannel overlay |
| 06 | [BGP Fundamentals](lessons/06-bgp-fundamentals.md) | BGP topology, Route Reflector, eBGP with ToR, BFD |
| 07 | [Bare Metal Network Infrastructure](lessons/07-bare-metal-network-infrastructure.md) | Spine-Leaf, bonding, VLAN design, jumbo frames |

### Track B — CNI Plugins and eBPF

| # | Lesson | Topics |
|---|--------|--------|
| 08 | [Cloud Provider Networking](lessons/08-cloud-provider-networking.md) | AWS VPC CNI, GKE Alias IPs, AKS Azure CNI |
| 09 | [CNI Specification](lessons/09-cni-specification.md) | CNI spec, ADD/DEL, IPAM plugins |
| 10 | [eBPF and XDP](lessons/10-ebpf-xdp.md) | XDP, TC hooks, BPF maps, bpftool |
| 11 | [Calico CNI Deep Dive](lessons/11-calico-cni-deep-dive.md) | Felix, BIRD, BGP, IPAM blocks, eBPF dataplane |
| 12 | [Cilium CNI and eBPF Dataplane](lessons/12-cilium-cni-ebpf.md) | eBPF identity policy, kube-proxy replacement, Hubble |

### Track C — Kubernetes Networking

| # | Lesson | Topics |
|---|--------|--------|
| 13 | [Kubernetes Services and kube-proxy](lessons/13-kubernetes-services-kube-proxy.md) | ClusterIP, NodePort, LB, EndpointSlices, IPVS |
| 14 | [CoreDNS and Service Discovery](lessons/14-coredns-service-discovery.md) | Corefile, ndots:5, NodeLocal DNSCache, stub zones |
| 15 | [IPv6 and Dual-Stack](lessons/15-ipv6-dual-stack.md) | dual-stack setup, ipFamilyPolicy, NDP, cloud support |
| 16 | [Network Policies](lessons/16-network-policies.md) | default-deny, selectors, L7 policy, FQDN egress |

### Track D — Ingress and Load Balancing

| # | Lesson | Topics |
|---|--------|--------|
| 17 | [Ingress Controllers](lessons/17-ingress-controllers.md) | NGINX, Traefik, TLS, cert-manager |
| 18 | [Gateway API](lessons/18-gateway-api.md) | GatewayClass, HTTPRoute, TCPRoute, GRPCRoute, v1 |
| 19 | [MetalLB and kube-vip](lessons/19-metallb-kube-vip.md) | L2 mode, BGP mode, shared IPs |
| 20 | [Cloud Provider Load Balancers](lessons/20-cloud-load-balancers.md) | AWS NLB/ALB, GKE LB, AKS Standard LB |

### Track E — Service Mesh and Security

| # | Lesson | Topics |
|---|--------|--------|
| 21 | [Service Mesh with Istio](lessons/21-service-mesh-istio.md) | mTLS, AuthorizationPolicy, VirtualService, ambient mode |
| 22 | [Multi-Cluster Networking](lessons/22-multi-cluster-networking.md) | Cluster Mesh, Istio multi-cluster, Submariner, MCS API |
| 23 | [Network Security Hardening](lessons/23-network-security-hardening.md) | default-deny, metadata block, encryption, FQDN policy |
| 24 | [Network Observability and Troubleshooting](lessons/24-network-observability-troubleshooting.md) | Hubble, packet capture, latency, DNS debug |

### Track F — OpenShift Networking

| # | Lesson | Topics |
|---|--------|--------|
| 25 | [OpenShift Networking Overview](lessons/25-openshift-networking-overview.md) | CNO, OVN-Kubernetes, namespace isolation |
| 26 | [OVN-Kubernetes](lessons/26-ovn-kubernetes.md) | OVS, ACLs, Geneve tunnels, IPsec |
| 27 | [OpenShift Routes and HAProxy](lessons/27-openshift-routes-haproxy.md) | Route CRD, edge/passthrough/reencrypt, A/B routing |
| 28 | [OpenShift EgressIP and EgressFirewall](lessons/28-openshift-egress.md) | EgressIP, EgressFirewall, DNS-based egress rules |

### Track G — AWS Networking

| # | Lesson | Topics |
|---|--------|--------|
| 29 | [AWS EKS Networking Deep Dive](lessons/29-aws-eks-networking.md) | VPC CNI, ENI limits, prefix delegation, Security Groups for Pods |
| 30 | [AWS VPC Design for Kubernetes](lessons/30-aws-vpc-design.md) | VPC sizing, subnet tags, ENIConfig, VPC endpoints |
| 31 | [AWS Load Balancer Controller](lessons/31-aws-load-balancer-controller.md) | NLB, ALB, IngressGroup, weighted routing, IRSA |
| 32 | [AWS Hybrid and Multi-Cluster](lessons/32-aws-hybrid-multicluster.md) | VPC peering, Transit Gateway, Direct Connect |

### Track H — GitOps

| # | Lesson | Topics |
|---|--------|--------|
| 33 | [ArgoCD and GitOps](lessons/33-argocd-gitops.md) | App CRD, sync waves, multi-cluster deploy, NetworkPolicy drift |

### Track I — AI Platform & Observability

| # | Lesson | Topics |
|---|--------|--------|
| 34 | [AI Platform Networking](lessons/34-ai-platform-networking.md) | RDMA, SR-IOV, Multus, RoCE v2, GPU Operator, rail topology |
| 40 | [OpenTelemetry for K8s Network Engineers](lessons/40-opentelemetry-network-observability.md) | OBI v1.0, K8s Operator, Hubble OTLP, network sem-convs, OTTL v1, profiling |

### Track J — Security and Compliance

| # | Lesson | Topics |
|---|--------|--------|
| 35 | [Tetragon: eBPF Runtime Security](lessons/35-tetragon-ebpf-runtime-security.md) | TracingPolicy, kprobes, Sigkill/Post actions, HIPAA §164.312(b) audit |
| 36 | [KubeEdge and Industrial Edge Networking](lessons/36-kubeedge-industrial-edge-networking.md) | EdgeHub, MetaManager, Purdue model, IEC 62443, disconnected ops |
| 37 | [Compliance Networking](lessons/37-compliance-networking.md) | HIPAA, PCI-DSS v4.0, IEC 62443, GDPR — exact NetworkPolicy YAML + auditor evidence |
| 38 | [Multus CNI and Multi-Homed Pods](lessons/38-multus-cni.md) | macvlan/ipvlan/SR-IOV delegates, AI/GPU RDMA, OT/IT edge separation |
| 39 | [Network Incident Management, SLOs, and RCA](lessons/39-network-incident-management-slo-rca.md) | SLOs, error budgets, multiwindow alerting, 5-why RCA, blameless postmortem, OTel/eBPF, compliance runbooks |

---

## CF Networking — 23 lessons

### Track CF-A — Platform Foundations

| # | Lesson | Topics |
|---|--------|--------|
| cf-01 | [Platform Architecture](docs/cf/cf-01-platform-architecture.md) | CF components, Diego, Garden, BBS, routing architecture |
| cf-02 | [Garden Container Networking](docs/cf/cf-02-garden-container-networking.md) | Garden-runC, container lifecycle, network setup hooks |
| cf-03 | [BOSH DNS](docs/cf/cf-03-bosh-dns.md) | BOSH DNS, aliases, health checks |
| cf-04 | [IPAM](docs/cf/cf-04-ipam.md) | Subnet allocation, container IP assignment, Silk IPAM |

### Track CF-B — Overlay and Policy

| # | Lesson | Topics |
|---|--------|--------|
| cf-05 | [Silk CNI and VXLAN](docs/cf/cf-05-silk-cni-vxlan.md) | Silk CNI, VXLAN overlay, VTEP setup, cross-cell traffic |
| cf-06 | [VXLAN Policy Agent](docs/cf/cf-06-vxlan-policy-agent.md) | Policy enforcement via iptables |
| cf-07 | [Application Security Groups](docs/cf/cf-07-application-security-groups.md) | ASG egress rules, staging/running ASGs, PCI-DSS/HIPAA controls |
| cf-08 | [Garden Namespaces](docs/cf/cf-08-garden-namespaces-deep-dive.md) | Linux namespace isolation, user namespaces, rootless containers |

### Track CF-C — Routing Layer

| # | Lesson | Topics |
|---|--------|--------|
| cf-09 | [Gorouter](docs/cf/cf-09-gorouter.md) | HTTP/WebSocket routing, route table, sticky sessions, TLS termination |
| cf-10 | [TCP Router](docs/cf/cf-10-tcp-router.md) | TCP routing tier, port allocation, HAProxy integration |
| cf-11 | [Routes and Domains](docs/cf/cf-11-routes-domains.md) | Shared/private domains, route mapping, blue-green routing |
| cf-12 | [Service Discovery](docs/cf/cf-12-service-discovery.md) | Internal routes, `apps.internal` domain, C2C DNS |

### Track CF-D — Security and Isolation

| # | Lesson | Topics |
|---|--------|--------|
| cf-13 | [Container-to-Container Network Policies](docs/cf/cf-13-c2c-network-policies.md) | C2C policy API, Silk enforcement, allow-list model |
| cf-14 | [TLS Certificates](docs/cf/cf-14-tls-certificates.md) | CredHub, certificate rotation, mTLS between platform components |
| cf-15 | [Org and Space Isolation](docs/cf/cf-15-org-space-isolation.md) | Multi-tenancy, isolation segments, IEC 62443 zone mapping |

### Track CF-E — Observability

| # | Lesson | Topics |
|---|--------|--------|
| cf-16 | [Observability and Troubleshooting](docs/cf/cf-16-observability-troubleshooting.md) | Loggregator, metrics-discovery, network flow visibility |
| cf-17 | [Logging and Metrics](docs/cf/cf-17-logging-metrics-performance.md) | Log cache, syslog drains, Prometheus scraping |

### Track CF-F — Migration and Korifi

| # | Lesson | Topics |
|---|--------|--------|
| cf-18 | [Korifi: CF on Kubernetes](docs/cf/cf-18-korifi-cf-on-kubernetes.md) | CF API on K8s, Korifi controllers, kpack, networking CRDs |
| cf-19 | [CF-to-K8s Migration Patterns](docs/cf/cf-19-cf-to-k8s-migration-patterns.md) | Lift-and-shift, strangler fig, networking equivalence mapping |

### Track CF-G — Comparison

| # | Lesson | Topics |
|---|--------|--------|
| cf-20 | [CF vs K8s Comparison](docs/cf/cf-20-cf-vs-k8s-comparison.md) | Side-by-side: routing, networking, isolation, observability |

### Track CF-H — Security and Compliance

| # | Lesson | Topics |
|---|--------|--------|
| cf-21 | [Compliance Networking](docs/cf/cf-21-compliance-networking.md) | HIPAA/PCI-DSS/IEC 62443/GDPR via ASGs, C2C policies, TLS |
| cf-22 | [SAP BTP Networking](docs/cf/cf-22-sap-btp-networking.md) | Private Link, Cloud Connector, BTP CF vs Kyma boundary |

---

## Cert prep guides

| Guide | Covers |
|-------|--------|
| [CKNE + CCA Exam Prep](docs/ckne-prep.md) | 5 CKNE domains + 8 CCA domains → lesson map, study paths, exam traps |
| [CKA + CKS Exam Prep](docs/cka-cks-prep.md) | CKA Services & Networking domain + all 6 CKS domains → lesson map |
| [Compliance Learning Paths](docs/compliance-paths.md) | Sector paths for medtech / banking / manufacturing / big tech in CH, DE, USA |

---

## Learning path

```
Phase 1  Linux Foundations        01–07   kernel primitives, namespaces, BGP, bare metal
Phase 2  CNI & eBPF               08–12   CNI spec, eBPF/XDP, Calico, Cilium
Phase 3  Kubernetes Networking    13–16   Services, CoreDNS, IPv6, NetworkPolicy
Phase 4  Ingress & LB             17–20   Ingress, Gateway API v1, MetalLB, cloud LBs
Phase 5  Service Mesh & Security  21–24   Istio, multi-cluster, hardening, observability
Phase 6  OpenShift                25–28   OVN-K, Routes, EgressIP
Phase 7  AWS                      29–32   EKS, VPC design, LB Controller, hybrid
Phase 8  GitOps & AI              33–34   ArgoCD, RDMA/SR-IOV/rail topology
Phase 9  Security & Compliance    35–39   Tetragon, KubeEdge, HIPAA/PCI/IEC/GDPR, Multus, Incident Management/SLOs/RCA
Phase 10 OTel & Observability     40      OBI v1.0, K8s OTel Operator, Hubble OTLP, OTTL v1
Phase 10 CF Networking            cf-01–cf-22   Garden, Silk, Gorouter, ASGs, BTP, compliance
Phase 11 Migration & Cheat Sheets           CF→K8s patterns, 16 quick-reference sheets
```

---

## Key tools

| Tool | Purpose |
|------|---------|
| `cilium` CLI | Cilium management, status, encryption |
| `hubble` CLI | eBPF-based flow inspection |
| `calicoctl` | Calico resource management |
| `istioctl` | Istio installation and diagnosis |
| `bpftool` | Inspect BPF programs and maps |
| `netshoot` | Network troubleshooting container |
| `ksniff` | tcpdump via kubectl plugin |
| `argocd` CLI | ArgoCD application management |
| `cf` CLI | Cloud Foundry application management |
| `keadm` | KubeEdge node join and management |

---

## Reference

- [CNI Specification](https://github.com/containernetworking/cni/blob/main/SPEC.md)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [Cilium / Tetragon docs](https://docs.cilium.io)
- [KubeEdge docs](https://kubeedge.io/docs/)
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)
- [CF Silk CNI](https://github.com/cloudfoundry/silk)
- [Korifi](https://github.com/cloudfoundry/korifi)
- [Free resources per lesson](docs/RESOURCES.md)
