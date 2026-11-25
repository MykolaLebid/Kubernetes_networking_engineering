# Compliance Learning Paths

Sector-specific study paths for engineers in regulated industries in Switzerland, Germany, and the USA.

---

## How to use this guide

Each path lists lessons in the order that builds understanding fastest for your sector. All paths assume you complete the core K8s foundation first (Lessons 01–16).

---

## Foundation (all sectors — start here)

```
Lesson 01 → 04   Linux primitives, namespaces, veth, bridges
Lesson 09        CNI specification — understand the enforcement gap
Lesson 13 → 14   Services + CoreDNS
Lesson 16        NetworkPolicy — default-deny patterns, CNI prerequisite
```

---

## Medtech / Healthcare IT
**Countries:** USA (HIPAA), Switzerland (Swissmedic + GDPR), Germany (MBO-Ä + GDPR)
**Roles:** Platform engineer, SRE, cloud architect at Roche, Novartis, Siemens Healthineers, Epic, Cerner

```
Core foundation (01–16)
  ↓
Lesson 12   Cilium — WireGuard node encryption for HIPAA §164.312(e)(1)
Lesson 23   Network security hardening
Lesson 35   Tetragon — eBPF runtime security for HIPAA §164.312(b) audit controls
Lesson 37   Compliance networking — HIPAA control mapping, exact YAML + auditor evidence
  ↓
Certifications: CKNE → CCA → CKS
```

**Key skills to demonstrate in interviews:**
- Default-deny NetworkPolicy + CNI enforcement verification
- WireGuard encryption via Cilium (`cilium encrypt status`)
- Tetragon TracingPolicy for file access audit (`security_file_open`)
- Mapping K8s network controls to HIPAA §164.312 controls

---

## Banking / Financial Services
**Countries:** USA (PCI-DSS, SOX), Switzerland (FINMA, PCI-DSS), Germany (MaRisk, BaFin, PCI-DSS)
**Roles:** Platform engineer, SRE, cloud security architect at UBS, Credit Suisse, Deutsche Bank, JPMorgan, Goldman

```
Core foundation (01–16)
  ↓
Lesson 12   Cilium — FQDN egress filtering (PCI-DSS Req 1.3.2), identity-based policy
Lesson 23   Network security hardening
Lesson 35   Tetragon — audit trail for PCI-DSS Req 10.2 (runtime process logging)
Lesson 37   Compliance networking — PCI-DSS CDE segmentation, exact YAML + auditor evidence
  ↓
CF path (if working with SAP BTP / Cloud Foundry):
  CF-07   ASGs as PCI-DSS controls
  CF-21   CF compliance networking
  CF-22   SAP BTP Private Link + subaccount isolation
  ↓
Certifications: CKNE → CCA → CKS
```

**Key skills to demonstrate in interviews:**
- CDE namespace isolation (default-deny + FQDN egress to Visa/Mastercard/Stripe only)
- Tetragon process audit with 12-month log retention
- Cross-namespace (cross-zone) policy via CiliumNetworkPolicy
- BTP Private Link for database connectivity without public internet

---

## Manufacturing / IoT / Industry 4.0
**Countries:** Germany (NIS2, IEC 62443), Switzerland (IEC 62443), USA (IEC 62443, NERC CIP)
**Roles:** OT/IT platform engineer, edge computing architect at Siemens, Bosch, ABB, GE, Honeywell, TRUMPF

```
Core foundation (01–16)
  ↓
Lesson 05   VXLAN and overlay — understand OT/IT separation
Lesson 36   KubeEdge — disconnected edge operation, Purdue model, IEC 62443 zones
Lesson 37   Compliance networking — IEC 62443 zone/conduit mapping to K8s NetworkPolicy
Lesson 38   Multus CNI — OT/IT dual-NIC edge pods
Lesson 35   Tetragon — runtime security on edge nodes
  ↓
Certifications: CKNE → ISA/IEC 62443 Cybersecurity Certificate
```

**Key skills to demonstrate in interviews:**
- KubeEdge disconnected operation (MetaManager SQLite cache, `keadm join`)
- Multus dual-NIC pods for OT/IT separation (eth0 = K8s control, net1 = OT VLAN)
- IEC 62443 zone annotation on K8s namespaces + conduit NetworkPolicy
- Edge pod survival during 4-hour WAN outage

---

## Big Tech / Hyperscalers
**Countries:** USA (AWS/GCP/Azure platform teams), Germany (SAP, Zalando, Aleph Alpha), Switzerland (Google Zurich, Microsoft)
**Roles:** Platform engineer, SRE, cloud-native architect

```
Core foundation (01–16)
  ↓
Lesson 10   eBPF and XDP — understand the dataplane
Lesson 12   Cilium — full depth: kube-proxy replacement, Hubble, Cluster Mesh, ACNS
Lesson 22   Multi-cluster networking — Cluster Mesh, global services
Lesson 24   Observability — Hubble flows, OpenTelemetry
Lesson 34   AI platform networking — SR-IOV, RDMA, NCCL, rail topology
Lesson 38   Multus CNI — multi-homed GPU pods
  ↓
Certifications: CKNE → CCA → CKS
```

**Key skills to demonstrate in interviews:**
- Cilium kube-proxy replacement (`kubeProxyReplacement=strict`)
- Hubble flow filtering and L7 visibility
- Cluster Mesh multi-cluster service discovery
- NCCL/RDMA rail-optimized topology for AI training

---

## SRE (all sectors)

```
Core foundation (01–16)
  ↓
Lesson 24   Network observability and troubleshooting (the SRE bread-and-butter lesson)
Lesson 12   Cilium + Hubble — flow-based incident investigation
Lesson 35   Tetragon — process-level debugging, kernel-attributed network events
Lesson 21   Istio / service mesh — distributed tracing, mTLS debugging
  ↓
Then sector-specific path above
```

**Key SRE interview skills:**
- `hubble observe --pod X --follow` for live traffic debugging
- Correlating Tetragon process events with Hubble network flows
- `kubectl exec ds/cilium -- cilium monitor --type policy-verdict` for policy drops
- Network chaos engineering concepts (Chaos Mesh, Toxiproxy)

---

## Certification order by sector

| Sector | Recommended order |
|---|---|
| Medtech | CKA → CKNE → CCA → CKS |
| Banking | CKA → CKNE → CCA → CKS |
| Manufacturing | CKA → CKNE → ISA/IEC 62443 |
| Big Tech SRE | CKA → CKNE → CCA → CKS |
| CF/BTP specialist | CKA → CKNE → CCA (+ Korifi/CF knowledge) |

---

*See also: [CKNE + CCA Exam Prep](ckne-prep.md) · [CKA + CKS Exam Prep](cka-cks-prep.md)*
