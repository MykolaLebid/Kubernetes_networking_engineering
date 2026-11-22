# Lesson 16 — Network Policies: Microsegmentation

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 13 — Kubernetes Services](13-kubernetes-services-kube-proxy.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl)
kubectl get netpol -A
kubectl get pods -A -o wide | head -15

# Terminal 2 — minikube Linux node
minikube ssh
# Inspect CNI-enforced iptables rules (Calico)
sudo iptables -L | grep -i cali | head -20
# Or for Cilium: sudo bpftool map dump name cilium_policy 2>/dev/null | head -20
```

---

## Why This Matters

By default, all pods in a Kubernetes cluster can communicate with each other. NetworkPolicy implements microsegmentation — the principle of least-privilege access at the network layer. It is essential for multi-tenant clusters, compliance requirements (PCI-DSS, HIPAA), and defense-in-depth security.

---

## 1. The Default Model

Without any NetworkPolicy, all ingress and all egress between pods is **allowed** (flat network model). Applying a NetworkPolicy to a pod's selector activates enforcement and **denies all traffic not explicitly permitted**.

```
No policy applied → pod is non-isolated → all traffic allowed
Policy applied    → pod is isolated → only specified traffic allowed
```

---

## 2. NetworkPolicy Anatomy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-policy
  namespace: default         # policies are namespace-scoped
spec:
  podSelector:               # pods this policy applies TO
    matchLabels:
      app: web

  policyTypes:               # which directions this policy governs
    - Ingress
    - Egress

  ingress:                   # whitelist of allowed inbound connections
    - from:
        - podSelector:       # from pods with these labels (same namespace)
            matchLabels:
              app: frontend
        - namespaceSelector: # from pods in namespaces with this label
            matchLabels:
              env: production
      ports:
        - protocol: TCP
          port: 80

  egress:                    # whitelist of allowed outbound connections
    - to:
        - podSelector:
            matchLabels:
              app: db
      ports:
        - protocol: TCP
          port: 5432
    - to: []                 # DNS egress (required or DNS breaks)
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

---

## 3. Selector Combinations

```yaml
# AND condition: pod must have BOTH labels
from:
  - podSelector:
      matchLabels:
        app: frontend
        env: production

# OR condition: separate from entries
from:
  - podSelector:
      matchLabels:
        app: frontend
  - podSelector:
      matchLabels:
        app: api

# AND between podSelector AND namespaceSelector
# (pod must match AND be in a matching namespace)
from:
  - podSelector:
      matchLabels:
        role: db-client
    namespaceSelector:
      matchLabels:
        project: billing

# Note: if podSelector and namespaceSelector are SEPARATE from entries,
# they are ORed. If they are in the SAME from entry, they are ANDed.
```

---

## 4. Common Policy Patterns

### Default Deny All (namespace baseline)
```yaml
# Apply first — sets default deny for the namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}      # matches all pods
  policyTypes:
    - Ingress
    - Egress
```

### Allow DNS (almost always needed with egress policies)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### Allow Prometheus Scraping
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app: prometheus
      ports:
        - port: 9090
```

### Allow from Specific CIDR (bare metal or on-prem)
```yaml
egress:
  - to:
      - ipBlock:
          cidr: 10.100.0.0/16    # corporate internal
          except:
            - 10.100.1.0/24      # exclude sensitive subnet
```

---

## 5. CNI Plugin Support

NetworkPolicy enforcement is **the CNI plugin's responsibility** — the Kubernetes API accepts any policy, but only plugins that implement it will enforce it.

| CNI Plugin | NetworkPolicy Support |
|------------|----------------------|
| Calico | Full (Kubernetes + its own CRDs) |
| Cilium | Full (Kubernetes + its own CRDs + L7) |
| Weave Net | Full |
| Flannel | None (use with Calico or Calico policy-only mode) |
| AWS VPC CNI | Partial (use Calico or Cilium on top) |
| GKE Dataplane v2 | Full (Cilium under the hood) |

---

## 6. Testing Network Policies

```bash
# Method 1: netcat connectivity test from inside a pod
kubectl run -it --rm tester --image=nicolaka/netshoot -- \
  nc -vz web.default.svc.cluster.local 80

# Method 2: Policy trace with Calico
calicoctl policy trace \
  --src-pod default/frontend \
  --dst-pod default/backend \
  --dst-port 8080

# Method 3: Cilium policy trace
cilium policy trace \
  --src-identity <id> \
  --dst-identity <id> \
  --dport 80

# Method 4: Use network-policy-api conformance tests
# https://github.com/kubernetes-sigs/network-policy-api
```

---

## 7. Calico NetworkPolicy Extras

```yaml
# Calico GlobalNetworkPolicy — cluster-wide, pre-namespace policies
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: allow-node-ports
spec:
  selector: all()
  ingress:
    - action: Allow
      protocol: TCP
      destination:
        ports: [30000-32767]   # NodePort range
  order: 100   # lower = higher priority

# Calico HostEndpoint — apply policy to node interfaces
apiVersion: projectcalico.org/v3
kind: HostEndpoint
metadata:
  name: node1-eth0
spec:
  interfaceName: eth0
  node: node1
  profiles:
    - node-profile
```

---

## 8. Cilium L7 Network Policy

Cilium can enforce policy at Layer 7 (HTTP, gRPC, Kafka).

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: http-policy
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          rules:
            http:
              - method: "GET"
                path: "/api/v1/.*"
              - method: "POST"
                path: "/api/v1/data"
                headers:
                  - "X-API-Key: .*"
```

---

## 9. Troubleshooting Network Policies

```bash
# 1. Confirm the policy is applied
kubectl get networkpolicy -n default
kubectl describe networkpolicy web-policy

# 2. Check if pod is isolated
# (if any policy selects it, the pod is isolated)
kubectl get networkpolicy -n default -o yaml | \
  grep -A5 "podSelector"

# 3. Test connectivity
kubectl exec -it frontend-pod -- curl -v http://web:80
# connection refused → pod unreachable, policy likely blocking
# timeout → policy dropping packets (not rejecting)

# 4. Calico: check what policy is applied
calicoctl get workloadendpoint -n default <pod-name> -o yaml | \
  grep -A20 "policies"

# 5. Calico: watch Felix deny logs
kubectl logs -n calico-system calico-node-xxxxx -c calico-node | \
  grep "Deny"

# 6. Cilium: watch dropped flows
hubble observe --verdict DROPPED --namespace default

# Common mistakes:
# 1. Missing DNS egress rule → DNS lookups fail → app sees "name not resolved"
# 2. OR vs AND selector confusion (same from vs separate from entries)
# 3. Policy in wrong namespace
# 4. Missing policyTypes declaration → only specified type enforced
# 5. Forgetting to allow health check IPs (bare metal LB)
```

---

## 10. Network Policy on Cloud Providers

### AWS EKS
```bash
# Option 1: Calico NetworkPolicy on EKS (without replacing VPC CNI)
kubectl apply -f calico-operator.yaml

# Option 2: Security Groups for Pods (AWS native)
# Apply SGs at pod level via SecurityGroupPolicy CRD
```

### GKE
```bash
# Enable NetworkPolicy at cluster creation (or update)
gcloud container clusters update my-cluster \
  --update-addons=NetworkPolicy=ENABLED
gcloud container clusters update my-cluster \
  --enable-network-policy
```

### AKS
```bash
# Enable Calico NetworkPolicy on AKS
az aks create --network-policy calico

# Or use Azure NPM (Azure Network Policy Manager)
az aks create --network-policy azure
```

---

## 11. Summary

| Concept | Detail |
|---------|--------|
| Default behavior | All pod-to-pod traffic allowed (no policies) |
| Policy activation | ANY policy selecting a pod isolates it |
| Selector logic | Same `from` entry = AND, separate entries = OR |
| DNS egress | Must be explicitly allowed with egress policies |
| L7 policy | Cilium only (Kubernetes NetworkPolicy is L4) |
| Testing | `nc`, Cilium Hubble, Calico `calicoctl policy trace` |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Isovalent: Cilium Host Firewall](https://isovalent.com/labs/cilium-host-firewall/) | Free | Enforce network policies at the host level with Cilium — extends standard NetworkPolicy to node traffic |
| [Killercoda Playground](https://killercoda.com/) | Free | Apply and test NetworkPolicy YAML, verify traffic is blocked with `kubectl exec` + `curl` |
| [Kubernetes Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes) | Free (GitHub) | 20+ ready-to-use NetworkPolicy examples covering default-deny, namespace isolation, CIDR rules — copy-paste into your cluster |
| [NetworkPolicy Editor (Cilium)](https://editor.networkpolicy.io/) | Free browser tool | Visual drag-and-drop NetworkPolicy editor — build policies graphically, export YAML, see the selector logic |

---

**Next:** [Lesson 17 — Ingress Controllers and L7 Load Balancing](17-ingress-controllers.md)
