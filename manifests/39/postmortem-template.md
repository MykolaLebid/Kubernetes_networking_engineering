---
# Postmortem template — Network Incident
# Use in conjunction with Lesson 39 five-layer RCA methodology
# Required sections for PCI-DSS Req 12.10.2 and HIPAA 45 CFR §164.308(a)(6)
# ---------------------------------------------------------------------------

## Network Incident Postmortem

**Title:**
**Date (UTC):**
**Severity:** P1 / P2 / P3
**Incident Commander:**
**Scribe:**

---

### Impact

- Duration: <!-- HH:MM UTC start --> → <!-- HH:MM UTC end --> = <!-- N --> minutes
- Services affected:
- Users / transactions affected:
- Error budget consumed (% of 30-day):
- Compliance scope: HIPAA PHI / PCI CDE / IEC 62443 / None

---

### Timeline (UTC)

| Time | Event | Source / Who detected |
|------|-------|----------------------|
|      |       |                      |

---

### Five-Layer RCA

| Layer | Checked | Finding |
|-------|---------|---------|
| L5 — Policy (NetworkPolicy / CiliumNetworkPolicy) | Yes / No | |
| L4 — K8s control plane (Service, EndpointSlice) | Yes / No | |
| L3 — CNI / overlay (Cilium status, BPF maps) | Yes / No | |
| L2 — Node networking (conntrack, ip_forward, MTU) | Yes / No | |
| L1 — Infrastructure (NIC, cloud SG, VPC routes) | Yes / No | |

---

### Root Cause (5-Why)

1. Why <!-- symptom -->?
   → <!-- answer 1 -->

2. Why <!-- answer 1 -->?
   → <!-- answer 2 -->

3. Why <!-- answer 2 -->?
   → <!-- answer 3 -->

4. Why <!-- answer 3 -->?
   → <!-- answer 4 -->

5. Why <!-- answer 4 -->?
   → <!-- root cause: process / SLO gap -->

**Root cause:**
**Contributing factors:**

---

### What Went Well

-

### What Went Wrong

-

---

### Action Items

| Action | Owner | Due | Prevents |
|--------|-------|-----|---------|
|        |       |     |         |

---

### Compliance Evidence

| Required | Location |
|----------|----------|
| Hubble flow logs (scope: impacted namespace, incident window) | |
| Tetragon audit events (scope: impacted nodes, incident window) | |
| Alertmanager firing/resolved timestamps | |
| Incident ticket URL | |
| Change record (if applicable) | |

<!-- PCI-DSS Req 12.10.2: document incident detection, response, containment, and corrective actions -->
<!-- HIPAA 45 CFR §164.308(a)(6): document security incidents and their outcomes -->
<!-- IEC 62443 Section 4.2: document cyber security incidents with timeline and lessons learned -->
