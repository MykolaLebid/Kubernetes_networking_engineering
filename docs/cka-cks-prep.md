# CKA & CKS Exam Prep Guide

Map of all exam domains to specific lessons in this course.

---

## CKA — Certified Kubernetes Administrator

### Exam at a glance

| Property | Detail |
|---|---|
| Format | Performance-based (live cluster tasks) |
| Duration | 2 hours |
| Passing score | 66% |
| Provider | Linux Foundation / CNCF |

### Domain map

| Domain | Weight | Primary lessons |
|---|---|---|
| **Storage** | 10% | — |
| **Troubleshooting** | 30% | [24](lessons/24-network-observability-troubleshooting.md), [14](lessons/14-coredns-service-discovery.md) |
| **Workloads & Scheduling** | 15% | — |
| **Cluster Architecture, Installation & Config** | 25% | [01](lessons/01-linux-networking-fundamentals.md)–[04](lessons/04-network-namespaces-deep-dive.md), [09](lessons/09-cni-specification.md) |
| **Services & Networking** | 20% | [13](lessons/13-kubernetes-services-kube-proxy.md), [14](lessons/14-coredns-service-discovery.md), [16](lessons/16-network-policies.md), [17](lessons/17-ingress-controllers.md), [18](lessons/18-gateway-api.md) |

### Networking-specific CKA tasks (most common exam questions)

| Task | Lessons |
|---|---|
| Debug pod-to-pod connectivity | 01, 04, 09 |
| Create and test NetworkPolicy | 16 |
| Configure CoreDNS with custom stub zone | 14 |
| Expose a Deployment via ClusterIP / NodePort / LoadBalancer | 13 |
| Configure Ingress with TLS | 17 |
| Debug Service not routing traffic | 13, 24 |
| Identify and fix CNI misconfiguration | 09 |

### Critical CKA traps (networking)

1. **NetworkPolicy requires a compatible CNI** — applying a policy on a cluster with Flannel has zero effect
2. **CoreDNS ndots:5** — test with FQDN if short name resolution fails
3. **Service endpoints** — `kubectl get endpoints <svc>` before assuming the Service is broken

---

## CKS — Certified Kubernetes Security Specialist

### Exam at a glance

| Property | Detail |
|---|---|
| Format | Performance-based (live cluster tasks) |
| Duration | 2 hours |
| Passing score | 67% |
| Prerequisite | Valid CKA |
| Provider | Linux Foundation / CNCF |

### Domain map

| Domain | Weight | Primary lessons |
|---|---|---|
| **Cluster Setup** | 15% | [23](lessons/23-network-security-hardening.md), [16](lessons/16-network-policies.md) |
| **Cluster Hardening** | 15% | [23](lessons/23-network-security-hardening.md) |
| **System Hardening** | 10% | [35](lessons/35-tetragon-ebpf-runtime-security.md) |
| **Minimize Microservice Vulnerabilities** | 20% | [16](lessons/16-network-policies.md), [12](lessons/12-cilium-cni-ebpf.md), [21](lessons/21-service-mesh-istio.md) |
| **Supply Chain Security** | 20% | — |
| **Monitoring, Logging & Runtime Security** | 20% | [35](lessons/35-tetragon-ebpf-runtime-security.md), [24](lessons/24-network-observability-troubleshooting.md), [40](lessons/40-opentelemetry-network-observability.md) |

### Networking-specific CKS tasks

| Task | Lessons |
|---|---|
| Implement default-deny NetworkPolicy | 16, 37 |
| Configure mTLS between pods (Cilium or Istio) | 12, 21 |
| Enable WireGuard node encryption | 12 |
| Write Tetragon TracingPolicy to block shell exec | 35 |
| Audit runtime process execution | 35 |
| Restrict egress to specific FQDNs | 12, 37 |
| Enable Falco or Tetragon for runtime detection | 35 |
| Harden Ingress with TLS and security headers | 17, 23 |

### Critical CKS traps (networking)

1. **60% of CKS is supply chain + microservice + runtime** — not just NetworkPolicy
2. **mTLS exam questions** often ask Cilium *or* Istio — know both
3. **Tetragon vs Falco** — both appear in exam; Tetragon uses eBPF (kernel-level), Falco uses syscall interception

---

## Recommended combined path

```
CKA (foundation) → CKNE (networking depth) → CCA (Cilium/eBPF) → CKS (security)
```

For regulated sectors (banking, medtech, manufacturing), add after CKS:
- **ISA/IEC 62443** certification (manufacturing/OT)
- Vendor-specific: Isovalent Cilium labs, Tetrate Istio certification

---

*Verify current domain weights at [training.linuxfoundation.org](https://training.linuxfoundation.org) before sitting the exam — weights change between versions.*
