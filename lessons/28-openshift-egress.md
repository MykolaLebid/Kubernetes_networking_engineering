# Lesson 28 — OpenShift EgressIP and EgressFirewall

> **Track:** OpenShift Networking  
> **Prerequisites:** [Lesson 16 — Network Policies](16-network-policies.md), [Lesson 25 — OpenShift Overview](25-openshift-networking-overview.md)  
> **Duration:** ~2 hours

---

## Practice Setup

```bash
# Terminal 1 — oc CLI
oc get egressip -o wide 2>/dev/null
oc get egressfirewall -A 2>/dev/null

# Terminal 2 — oc
oc get nodes -o custom-columns='NAME:.metadata.name,EGRESS:.metadata.labels.k8s\.ovn\.org/egress-assignable'
oc describe egressip default 2>/dev/null | head -20
```

---

## Why This Matters

In vanilla Kubernetes, all pods on the same node share the node's IP for outbound traffic. OpenShift adds two powerful egress controls: **EgressIP** pins pods to a specific stable IP for outbound traffic (critical for firewall rules on external systems), and **EgressFirewall** restricts which external hosts a namespace can reach (egress policy without a service mesh).

---

## 1. The Egress Problem

```
Pod → NAT to node IP → external system
```

Without EgressIP:
- Pods on node A use `192.168.1.10` as source IP
- Pods on node B use `192.168.1.11` as source IP
- When pods reschedule, their source IP changes
- External firewalls that whitelist IPs break on pod rescheduling

With EgressIP:
- Namespace `billing` always uses `192.168.1.100` as source IP
- External DB firewall permanently whitelists `192.168.1.100`
- Pod rescheduling doesn't affect the source IP

---

## 2. EgressIP

```yaml
# Step 1: Mark nodes as EgressIP candidates
oc label node worker-1 k8s.ovn.org/egress-assignable=""
oc label node worker-2 k8s.ovn.org/egress-assignable=""

# Step 2: Create an EgressIP resource
apiVersion: k8s.ovn.org/v1
kind: EgressIP
metadata:
  name: billing-egress
spec:
  egressIPs:
    - 192.168.1.100     # must be in the same subnet as the node
    - 192.168.1.101     # second IP for HA failover
  namespaceSelector:
    matchLabels:
      egress: billing   # namespaces with this label use these IPs
  podSelector:          # optional: only specific pods within the namespace
    matchLabels:
      app: billing-processor
```

```bash
# Label the namespace
oc label namespace billing egress: billing

# Check EgressIP status
oc get egressip billing-egress -o yaml
# status:
#   items:
#     - egressIP: 192.168.1.100
#       node: worker-1          ← which node holds this IP
#     - egressIP: 192.168.1.101
#       node: worker-2          ← second IP on another node (HA)

# Verify from inside a pod
oc exec -n billing billing-pod -- curl ifconfig.me
# Should return 192.168.1.100
```

**How it works (OVN-Kubernetes):**
- OVN adds a SNAT rule: pods in the namespace → EgressIP
- The EgressIP is assigned as a secondary IP on the egress node's NIC
- If the node fails, OVN moves the IP to another `egress-assignable` node

---

## 3. EgressIP High Availability

```bash
# EgressIP is automatically HA when multiple nodes are assignable
# and multiple IPs are configured

# Check which node currently holds the EgressIP
oc get egressip -o wide
# NAME             EGRESSIPS         ASSIGNED NODE    ASSIGNED EGRESSIPS
# billing-egress   192.168.1.100     worker-1         192.168.1.100
#                  192.168.1.101     worker-2         192.168.1.101

# If worker-1 goes down, 192.168.1.100 moves to another assignable node
# Failover time: ~1 second (BFD-based detection)
```

---

## 4. EgressFirewall

EgressFirewall restricts which external destinations a namespace's pods can reach. Think of it as a per-namespace egress NetworkPolicy for external traffic.

```yaml
apiVersion: k8s.ovn.org/v1
kind: EgressFirewall
metadata:
  name: default
  namespace: production
spec:
  egress:
    # Allow specific external CIDR
    - type: Allow
      to:
        cidrSelector: 10.100.0.0/16    # corporate internal network

    # Allow specific DNS names
    - type: Allow
      to:
        dnsName: api.example.com
      ports:
        - protocol: TCP
          port: 443

    # Allow DNS resolution
    - type: Allow
      to:
        cidrSelector: 0.0.0.0/0
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

    # Deny everything else
    - type: Deny
      to:
        cidrSelector: 0.0.0.0/0
```

```bash
# Apply and verify
oc apply -f egress-firewall.yaml
oc get egressfirewall -n production

# Test
oc exec -n production app-pod -- curl -m5 https://api.example.com    # allowed
oc exec -n production app-pod -- curl -m5 https://google.com          # denied
```

---

## 5. EgressFirewall with DNS Names

DNS-based rules are resolved by the OVN-Kubernetes DNS interceptor — it watches DNS responses and updates the firewall rules automatically when IPs change.

```yaml
egress:
  - type: Allow
    to:
      dnsName: "*.amazonaws.com"   # wildcard DNS names supported
    ports:
      - protocol: TCP
        port: 443
```

```bash
# Check how DNS names are resolved in the firewall
oc logs -n openshift-ovn-kubernetes ovnkube-master-xxxxx -c northd | grep dns
```

---

## 6. EgressFirewall on OpenShift SDN (Legacy)

On older clusters still using OpenShift SDN, EgressFirewall was called `EgressNetworkPolicy`:

```yaml
# Legacy — OpenShift SDN only
apiVersion: network.openshift.io/v1
kind: EgressNetworkPolicy
metadata:
  name: default
  namespace: production
spec:
  egress:
    - type: Allow
      to:
        cidrSelector: 10.100.0.0/16
    - type: Deny
      to:
        cidrSelector: 0.0.0.0/0
```

```bash
# Check which resource to use
oc get network.config.openshift.io cluster \
  -o jsonpath='{.status.networkType}'
# OVNKubernetes → use EgressFirewall
# OpenShiftSDN  → use EgressNetworkPolicy
```

---

## 7. Troubleshooting Egress

```bash
# EgressIP: check which pods are affected
oc get egressip billing-egress -o yaml | grep -A5 "namespaceSelector\|podSelector"

# EgressIP: test source IP from pod
oc exec -n billing billing-pod -- curl -s ifconfig.me

# EgressIP: check node assignment
oc get egressip -o wide

# EgressFirewall: check if rule is blocking
oc exec -n production app-pod -- curl -v https://blocked-site.com
# Expected: connection timeout (Deny rule drops silently)

# EgressFirewall: view OVN ACLs
oc exec -n openshift-ovn-kubernetes ovnkube-master-xxxxx -- \
  ovn-nbctl acl-list production | grep Egress

# Common issues:
# 1. EgressIP not assigned → no egress-assignable nodes labeled
# 2. EgressIP not in node subnet → OVN can't assign it as secondary IP
# 3. EgressFirewall blocking DNS → missing UDP/TCP port 53 allow rule
# 4. DNS-based rule not matching → check OVN DNS cache timing
```

---

## 8. Summary

| Resource | Purpose | Scope |
|----------|---------|-------|
| EgressIP | Stable source IP for outbound traffic | Namespace or pod selector |
| EgressFirewall | Restrict external destinations | Per namespace |
| EgressNetworkPolicy | Legacy EgressFirewall (OpenShift SDN only) | Per namespace |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) | Free 30-day cluster | Apply EgressIP and EgressFirewall resources; test DNS-based egress rules; observe HA failover behavior |
| [Red Hat: EgressIP Documentation](https://docs.openshift.com/container-platform/latest/networking/ovn_kubernetes_network_provider/assigning-egress-ips-ovn.html) | Free | Official walkthrough with YAML examples — follow along in the Developer Sandbox |

---

**Next:** [Lesson 29 — AWS EKS Networking Deep Dive](29-aws-eks-networking.md)
