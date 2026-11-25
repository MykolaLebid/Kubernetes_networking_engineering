# CKNE & CCA Exam Prep Guide

This course covers every domain of two Linux Foundation certifications:

- **CKNE** — Certified Kubernetes Network Engineer (performance-based, 2 hours)
- **CCA** — Cilium Certified Associate (multiple choice, 90 minutes)

Both are hands-on, job-posting–recognized credentials in SRE, platform engineering, and cloud-native networking roles.

---

## CKNE — Certified Kubernetes Network Engineer

### Exam at a glance

| Property | Detail |
|---|---|
| Format | Performance-based (live cluster tasks) |
| Duration | 2 hours |
| Passing score | 66% |
| Provider | Linux Foundation / CNCF |
| Prerequisite | CKA recommended |

### Domain map

| Domain | Weight | Primary lessons | Key skills |
|---|---|---|---|
| **Service Networking & DNS** | 25% | [13](lessons/13-kubernetes-services-kube-proxy.md), [14](lessons/14-coredns-service-discovery.md), [18](lessons/18-gateway-api.md) | ClusterIP/NodePort/LoadBalancer, kube-proxy vs eBPF, CoreDNS customization, Gateway API v1.2, troubleshooting service traffic |
| **Network Security & Policy** | 25% | [16](lessons/16-network-policies.md), [23](lessons/23-network-security-hardening.md), [35](lessons/35-tetragon-ebpf-runtime-security.md) | default-deny NetworkPolicy, WireGuard node encryption, mTLS, pod-level auth, TLS certs for Gateways |
| **Advanced Traffic Management** | 20% | [17](lessons/17-ingress-controllers.md), [18](lessons/18-gateway-api.md), [21](lessons/21-service-mesh-istio.md), [22](lessons/22-multi-cluster-networking.md) | Ingress/Gateway routing, egress gateways, cross-cluster service discovery, load distribution |
| **Core Infrastructure & CNI** | 15% | [09](lessons/09-cni-specification.md), [11](lessons/11-calico-cni-deep-dive.md), [12](lessons/12-cilium-cni-ebpf.md), [38](lessons/38-multus-cni.md) | CNI plugin installation, IPAM, multi-interface pods (Multus), pod connectivity troubleshooting |
| **Observability** | 15% | [24](lessons/24-network-observability-troubleshooting.md), [12](lessons/12-cilium-cni-ebpf.md), [40](lessons/40-opentelemetry-network-observability.md) | Hubble flow inspection, L7 protocol visibility, metrics, end-to-end tracing, OTel/OBI zero-code instrumentation, traffic audit logs |

### Recommended study path

```
Week 1 — Foundations
  Lesson 01 → 04 (Linux primitives, namespaces)
  Lesson 09 (CNI spec — understand what CKNE Domain 4 is really testing)
  Lesson 13 → 14 (Services + CoreDNS — Domain 1, 25%)

Week 2 — Security (highest weight combined)
  Lesson 16 (NetworkPolicy — default-deny patterns, CNI enforcement gap)
  Lesson 12 (Cilium — identity-based policy, WireGuard, Hubble)
  Lesson 23 (Security hardening)
  Lesson 35 (Tetragon — runtime security, Domain 2 + CKS overlap)

Week 3 — Traffic + Multi-cluster
  Lesson 17 → 18 (Ingress, Gateway API v1.2)
  Lesson 21 (Istio / ambient mesh)
  Lesson 22 (Multi-cluster, Cluster Mesh)

Week 4 — Observability + Practice
  Lesson 24 (Observability, Hubble)
  Lesson 40 (OpenTelemetry: OBI v1.0, K8s Operator, Hubble OTLP, OTTL v1)
  Lab scripts: validate-13, validate-16, validate-09
  Full mock: deploy Cilium, write NetworkPolicy, configure Gateway, trace with Hubble
```

### Critical exam traps

1. **NetworkPolicy silent no-op** — applying a NetworkPolicy on a cluster without a CNI that implements it (e.g. Flannel) has zero effect. Always verify CNI before writing policies.
2. **Gateway API API versions** — use `gateway.networking.k8s.io/v1` for HTTPRoute and GRPCRoute (GA since v1.2). Do not use `v1alpha2` or `v1beta1` in exam tasks.
3. **kube-proxy vs eBPF** — Cilium with `kubeProxyReplacement=true` changes how services are implemented. Know which mode your cluster is using before debugging service connectivity.
4. **CoreDNS ndots** — the default `ndots:5` causes 4 failed lookups before a FQDN resolves. Know how to override in pod spec.

---

## CCA — Cilium Certified Associate

### Exam at a glance

| Property | Detail |
|---|---|
| Format | Multiple choice |
| Duration | 90 minutes |
| Passing score | 75% |
| Provider | Linux Foundation / CNCF |
| Prerequisite | None (Kubernetes knowledge recommended) |

### Domain map

| Domain | Weight | Primary lessons | Key concepts |
|---|---|---|---|
| **Architecture** | 20% | [12](lessons/12-cilium-cni-ebpf.md) | cilium-agent, cilium-operator, Hubble relay, IPAM modes, CiliumNode CRDs |
| **Network Policy** | 18% | [12](lessons/12-cilium-cni-ebpf.md), [16](lessons/16-network-policies.md) | Identity-based policy, L3/L4/L7 CiliumNetworkPolicy, FQDN egress filtering |
| **Service Mesh** | 16% | [12](lessons/12-cilium-cni-ebpf.md), [21](lessons/21-service-mesh-istio.md) | Ingress routing, Gateway API, WireGuard/mTLS encryption, ambient mesh vs sidecar |
| **Network Observability** | 10% | [24](lessons/24-network-observability-troubleshooting.md), [12](lessons/12-cilium-cni-ebpf.md) | Hubble CLI flows, L7 visibility, Hubble UI, flow filtering |
| **Installation & Configuration** | 10% | [12](lessons/12-cilium-cni-ebpf.md) | cilium CLI, helm values, connectivity test, `cilium status` |
| **Cluster Mesh** | 10% | [22](lessons/22-multi-cluster-networking.md) | clustermesh-apiserver, global services, cross-cluster NetworkPolicy |
| **eBPF** | 10% | [10](lessons/10-ebpf-xdp.md), [12](lessons/12-cilium-cni-ebpf.md) | eBPF vs iptables, BPF maps, TC programs, kube-proxy replacement |
| **BGP & External Networking** | 6% | [06](lessons/06-bgp-fundamentals.md), [12](lessons/12-cilium-cni-ebpf.md) | BGP Control Plane, CiliumBGPPeeringPolicy, LB IPAM |

### Recommended study path

```
Day 1-2: Lesson 10 (eBPF internals) → Lesson 12 (Cilium full deep dive)
Day 3:   Lesson 16 (NetworkPolicy) + CiliumNetworkPolicy YAML practice
Day 4:   Lesson 22 (Cluster Mesh) + Lesson 06 (BGP)
Day 5:   Lesson 24 (Hubble observability) + mock questions
```

### Critical exam traps

1. **CiliumNetworkPolicy vs NetworkPolicy** — Cilium respects standard `NetworkPolicy` but `CiliumNetworkPolicy` adds L7 (HTTP/gRPC/Kafka) and FQDN rules. Know which CRD to use for which requirement.
2. **Identity not IP** — Cilium policy uses numeric security identities derived from labels, not IP addresses. Policy does not break on pod reschedule.
3. **Cluster Mesh prerequisites** — clusters must have non-overlapping pod CIDRs and unique cluster names/IDs before enabling Cluster Mesh.
4. **kube-proxy replacement modes** — `disabled`, `probe`, `strict`. Know the difference and when each is appropriate.

---

## Combined cert path for regulated-sector engineers

If you work in banking, medtech, or manufacturing, pursue in this order:

```
CKA → CKNE → CCA → CKS
```

| Cert | Focus | Regulated-sector value |
|---|---|---|
| CKA | Cluster administration | Foundation |
| CKNE | Network engineering | Service mesh, NetworkPolicy, observability |
| CCA | Cilium/eBPF specialization | WireGuard, L7 policy, Hubble audit trails |
| CKS | Security hardening | Runtime security (Tetragon), supply chain, RBAC |

For manufacturing/IoT roles in Germany or Switzerland, additionally pursue **ISA/IEC 62443** credentials alongside this K8s path — see [Lesson 37](lessons/37-compliance-networking.md) for the mapping between IEC 62443 controls and K8s network configurations.

---

## What this course covers vs exam gaps

| CKNE skill | Covered | Where |
|---|---|---|
| CNI installation + IPAM | Yes | Lessons 09, 11, 12 |
| NetworkPolicy default-deny | Yes | Lesson 16 |
| Gateway API v1.2 | Yes | Lesson 18 |
| CoreDNS customization | Yes | Lesson 14 |
| Hubble flow inspection | Yes | Lessons 12, 24 |
| WireGuard node encryption | Yes | Lesson 12, 35 |
| Multi-interface pods (Multus) | Partial | Lesson 34, 38 |
| Egress gateway | Yes | Lessons 21, 22 |
| Cross-cluster service discovery | Yes | Lesson 22 |

| CCA skill | Covered | Where |
|---|---|---|
| Cilium architecture | Yes | Lesson 12 |
| L7 CiliumNetworkPolicy | Yes | Lesson 12 |
| FQDN egress filtering | Yes | Lesson 12 |
| Hubble CLI + UI | Yes | Lessons 12, 24 |
| Cluster Mesh | Yes | Lesson 22 |
| BGP Control Plane | Yes | Lessons 06, 12 |
| eBPF internals | Yes | Lessons 10, 12 |
| Ambient mesh | Yes | Lesson 21 |

---

*Last updated: 2026-11-25. CKNE and CCA exam blueprints change — verify current domain weights at [training.linuxfoundation.org](https://training.linuxfoundation.org) before sitting the exam.*
