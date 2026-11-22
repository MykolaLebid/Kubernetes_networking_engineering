# Lesson 33 — ArgoCD and GitOps for Network Configuration

> **Track:** GitOps & Delivery  
> **Prerequisites:** [Lesson 22 — Multi-Cluster Networking](22-multi-cluster-networking.md), [Lesson 16 — Network Policies](16-network-policies.md)  
> **Duration:** ~2 hours

---

## Practice Setup

```bash
# Terminal 1 — check ArgoCD is running
kubectl get pods -n argocd
kubectl get applications -n argocd

# Terminal 2 — watch sync events
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f
```

---

## Why This Matters

Network configuration in Kubernetes — NetworkPolicies, CoreDNS ConfigMaps, Ingress rules, CNI configs, service mesh policies — changes constantly. Applied manually with `kubectl apply`, these changes are invisible: no audit trail, no rollback, no consistency guarantee across clusters.

ArgoCD solves this by making Git the single source of truth. Every NetworkPolicy, every Ingress, every EgressFirewall lives in a repository and ArgoCD continuously reconciles the cluster to match it. For a network engineer, this means drift detection (someone edited a firewall rule by hand? ArgoCD flags it), guaranteed ordering (NetworkPolicy before app, CNI config before everything), and one-command rollback when a policy change breaks connectivity.

---

## 1. ArgoCD Architecture

```
  Git Repository (network-policies/, ingress/, cni-configs/)
         │
         │  pull (every 3 min or webhook)
         ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                      ArgoCD                                  │
  │                                                             │
  │  ┌──────────────┐    ┌──────────────────────────────────┐  │
  │  │  repo-server  │    │  application-controller          │  │
  │  │  - clones repo│    │  - watches Application CRDs      │  │
  │  │  - renders    │    │  - compares live vs desired      │  │
  │  │    manifests  │    │  - triggers sync                 │  │
  │  │  - Helm/Kust. │    └──────────────┬───────────────────┘  │
  │  └──────┬────────┘                   │                      │
  │         │                     ┌──────▼───────┐              │
  │  ┌──────▼────────┐            │  argocd-server│              │
  │  │     Redis      │            │  - REST API   │              │
  │  │  (cache layer) │            │  - Web UI     │              │
  │  └───────────────┘            │  - CLI target │              │
  │                               └───────────────┘              │
  │  ┌───────────────┐                                           │
  │  │  Dex (optional│                                           │
  │  │  OIDC/SSO)    │                                           │
  │  └───────────────┘                                           │
  └─────────────────────────────────────────────────────────────┘
         │  kubectl apply (uses cluster kubeconfig)
         ▼
  Kubernetes Cluster (NetworkPolicy, Ingress, Service, ...)
```

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s

# Get initial admin password
argocd admin initial-password -n argocd

# Port-forward the UI (or expose via Ingress/LoadBalancer)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

---

## 2. Application and ApplicationSet CRDs

### Application — single cluster, single source

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: network-policies
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/k8s-network-config
    targetRevision: main
    path: network-policies/production
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true        # delete resources removed from Git
      selfHeal: true     # re-apply if someone edits by hand
    syncOptions:
      - CreateNamespace=true
```

```bash
# CLI equivalent
argocd app create network-policies \
  --repo https://github.com/your-org/k8s-network-config \
  --path network-policies/production \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Check sync status
argocd app get network-policies
argocd app diff network-policies   # show what would change
argocd app sync network-policies   # force immediate sync
```

### Deploying CoreDNS config from Git

```yaml
# In Git: coredns/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        hosts /etc/coredns/NodeHosts {
          ttl 60
          fallthrough
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
    # Custom stub zone for internal services
    internal.corp:53 {
        forward . 10.100.0.53
    }
```

ArgoCD will detect drift the moment someone edits this ConfigMap manually.

---

## 3. Sync Waves for Network-Dependent Resources

Network resources must deploy in a specific order. A NetworkPolicy that blocks traffic must exist *before* the app starts, not after.

```
Sync Wave Order:

Wave -1: CRDs (Gateway API CRDs, Calico CRDs, cert-manager CRDs)
           │
Wave  0: CNI configuration (IPPool, BGPConfiguration, Cilium ConfigMap)
           │
Wave  1: NetworkPolicy (default-deny + allow rules)
           │
Wave  2: Application workloads (Deployments, StatefulSets)
           │
Wave  3: Ingress / Route / HTTPRoute (external access last)
           │
Wave  4: Monitoring (ServiceMonitor — after service exists)
```

```yaml
# Wave -1: CRDs first
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: gateways.gateway.networking.k8s.io
  annotations:
    argocd.argoproj.io/sync-wave: "-1"

---
# Wave 0: CNI IP pool
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: production-pool
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  cidr: 10.244.0.0/16
  ipipMode: Never
  natOutgoing: true

---
# Wave 1: NetworkPolicy before the app
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend

---
# Wave 2: Application
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: production
  annotations:
    argocd.argoproj.io/sync-wave: "2"

---
# Wave 3: Ingress (only after pods are ready)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backend-ingress
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

```bash
# Watch sync waves progress in real time
argocd app get network-stack --watch

# See which wave each resource is in
argocd app resources network-stack
```

---

## 4. Multi-Cluster Deployment with ApplicationSet

Deploy the same NetworkPolicy baseline to every cluster from a single Application definition.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: network-baseline
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: production   # only prod clusters
  template:
    metadata:
      name: "network-baseline-{{name}}"   # name = cluster name
    spec:
      project: network-team
      source:
        repoURL: https://github.com/your-org/k8s-network-config
        targetRevision: main
        path: network-baseline/
        helm:
          values: |
            clusterName: "{{name}}"
            clusterCIDR: "{{metadata.annotations.podCIDR}}"
      destination:
        server: "{{server}}"   # cluster API server URL
        namespace: kube-system
      syncPolicy:
        automated:
          selfHeal: true
```

```bash
# Register clusters with ArgoCD
argocd cluster add production-eu-west-1 --name eu-west-1
argocd cluster add production-us-east-1 --name us-east-1
argocd cluster add production-ap-southeast-1 --name ap-southeast-1

# Label clusters to match the ApplicationSet generator
kubectl label secret -n argocd eu-west-1 environment=production
kubectl label secret -n argocd us-east-1 environment=production

# ApplicationSet creates one Application per cluster automatically
kubectl get applications -n argocd | grep network-baseline

# Check sync status across all clusters
argocd app list | grep network-baseline
```

---

## 5. Health Checks for Network Resources

ArgoCD has built-in health checks for core Kubernetes resources. Network resources vary:

| Resource | ArgoCD Health Behavior |
|----------|----------------------|
| `Service` (ClusterIP) | Healthy immediately |
| `Service` (LoadBalancer) | Healthy when `.status.loadBalancer.ingress` is populated |
| `Ingress` | Healthy when `.status.loadBalancer.ingress` is populated |
| `NetworkPolicy` | Always **Healthy** — ArgoCD cannot verify enforcement |
| `Gateway` (Gateway API) | Healthy when `.status.conditions[Ready]=True` |
| `HTTPRoute` | Healthy when parent Gateway accepts it |
| `Certificate` (cert-manager) | Healthy when `.status.conditions[Ready]=True` |

NetworkPolicy is a critical gap — ArgoCD marks it healthy the moment it's applied, but cannot know if the CNI is actually enforcing it.

### Custom Lua health check for NetworkPolicy

```lua
-- In argocd-cm ConfigMap, resource.customizations section:
-- resource.customizations.health.networking.k8s.io_NetworkPolicy: |
hs = {}
if obj.metadata.creationTimestamp == nil then
  hs.status = "Progressing"
  hs.message = "NetworkPolicy not yet created"
  return hs
end
-- Check for a custom annotation set by a policy verification job
if obj.metadata.annotations ~= nil then
  if obj.metadata.annotations["network-policy/verified"] == "true" then
    hs.status = "Healthy"
    hs.message = "Policy applied and verified"
    return hs
  end
end
hs.status = "Degraded"
hs.message = "Policy applied but not verified — run policy conformance test"
return hs
```

```yaml
# In argocd-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.health.networking.k8s.io_NetworkPolicy: |
    hs = {}
    hs.status = "Healthy"
    hs.message = "Applied (enforcement depends on CNI)"
    return hs
```

---

## 6. Detecting Network Policy Drift

`selfHeal: true` means ArgoCD detects and reverses any out-of-band change within seconds.

```bash
# Scenario: network engineer manually tightens a firewall rule
kubectl patch networkpolicy allow-frontend-to-backend -n production \
  --type='json' -p='[{"op":"remove","path":"/spec/ingress/0/ports"}]'

# ArgoCD detects the diff within ~3 minutes (or immediately via webhook)
argocd app get network-policies
# STATUS: OutOfSync
# MESSAGE: NetworkPolicy production/allow-frontend-to-backend
#          spec.ingress[0].ports: missing (live) vs [{port:8080}] (desired)

# With selfHeal=true: ArgoCD automatically reverts it
# Without selfHeal: notify and wait for manual sync

# To allow intentional overrides, use ignoreDifferences:
spec:
  ignoreDifferences:
    - group: networking.k8s.io
      kind: NetworkPolicy
      jsonPointers:
        - /metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration
```

```bash
# Webhook setup (GitHub): push-triggered sync instead of poll
argocd app set network-policies --sync-policy automated
# Configure webhook in GitHub repo settings:
# URL: https://argocd.your-domain.com/api/webhook
# Secret: $(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.webhook\.github\.secret}' | base64 -d)
```

---

## 7. Argo Rollouts: Progressive Delivery with Network Integration

Argo Rollouts enables canary and blue-green deployments with network-layer traffic splitting.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: backend
spec:
  strategy:
    canary:
      canaryService: backend-canary   # separate Service for canary pods
      stableService: backend-stable   # Service for stable pods
      trafficRouting:
        istio:
          virtualService:
            name: backend-vsvc
            routes:
              - primary
      steps:
        - setWeight: 10    # 10% traffic to canary
        - pause: {duration: 5m}
        - analysis:
            templates:
              - templateName: success-rate
        - setWeight: 50
        - pause: {duration: 5m}
        - setWeight: 100
```

The `VirtualService` is updated automatically by the Rollout controller:

```yaml
# ArgoCD syncs this; Rollouts controller modifies weights during deployment
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: backend-vsvc
spec:
  http:
    - name: primary
      route:
        - destination:
            host: backend-stable
          weight: 90      # Rollout controller updates this
        - destination:
            host: backend-canary
          weight: 10
```

---

## 8. Practical: Zero-Trust Network Stack via GitOps

### Git repository structure

```
k8s-network-config/
├── network-baseline/
│   ├── default-deny.yaml         # wave 0: deny-all NetworkPolicy
│   ├── allow-dns.yaml            # wave 0: allow CoreDNS egress
│   ├── allow-monitoring.yaml     # wave 0: allow Prometheus scraping
│   └── kustomization.yaml
├── ingress/
│   ├── nginx-values.yaml         # wave 1: NGINX Ingress controller
│   ├── cert-manager.yaml         # wave 1: cert-manager
│   └── cluster-issuer.yaml       # wave 2: Let's Encrypt ClusterIssuer
├── applications/
│   └── frontend/
│       ├── networkpolicy.yaml    # wave 1
│       ├── deployment.yaml       # wave 2
│       ├── service.yaml          # wave 2
│       ├── ingress.yaml          # wave 3
│       └── certificate.yaml      # wave 3
└── applicationset.yaml
```

### Default-deny as wave 0 (foundation of zero-trust)

```yaml
# network-baseline/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
  annotations:
    argocd.argoproj.io/sync-wave: "0"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# Always allow DNS (without this, pods can't resolve service names)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: production
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### ApplicationSet deploying the full stack

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: zero-trust-stack
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: production-eu
            url: https://eks-eu.example.com
          - cluster: production-us
            url: https://eks-us.example.com
  template:
    metadata:
      name: "zero-trust-{{cluster}}"
    spec:
      source:
        repoURL: https://github.com/your-org/k8s-network-config
        path: .
        targetRevision: main
      destination:
        server: "{{url}}"
        namespace: production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - RespectIgnoreDifferences=true
          - ServerSideApply=true
```

---

## 9. Troubleshooting

### ArgoCD blocked by its own NetworkPolicy

The most common issue: you deploy a default-deny NetworkPolicy and ArgoCD can no longer reach the cluster API or webhook.

```yaml
# Always include this in your network-baseline:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-argocd-server
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"   # must exist BEFORE anything else
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-server
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - {}   # allow all inbound to ArgoCD UI/API
  egress:
    - {}   # allow ArgoCD to reach all cluster APIs
```

### Sync stuck on a resource

```bash
# See detailed sync error
argocd app sync network-policies --dry-run
argocd app get network-policies --show-operation

# Common causes for network resources:
# 1. CRD not installed → sync wave -1 missing
# 2. NetworkPolicy blocking ArgoCD webhook → add allow rule
# 3. Resource finalizer preventing deletion → check for calico/cilium finalizers
# 4. RBAC: ArgoCD service account lacks permission for custom CRDs
kubectl auth can-i create networkpolicies --as=system:serviceaccount:argocd:argocd-application-controller

# 5. Namespace not created → add CreateNamespace=true syncOption
```

### Resource health unknown

```bash
# Unknown health = ArgoCD has no health check for this resource type
# Common for: BGPPeer, IPPool, EgressIP, Gateway API types
argocd app get network-policies | grep Unknown

# Fix: add custom health check in argocd-cm, or use:
kubectl annotate application network-policies \
  argocd.argoproj.io/ignore-resource-updates='{"bgppeers.projectcalico.org": ["status"]}' -n argocd
```

### Webhook delivery failures

```bash
# Check if webhook is reachable from GitHub/GitLab
# ArgoCD server must be accessible from the internet (or use pull-based polling)
kubectl get svc argocd-server -n argocd   # must have external IP

# Check webhook secret matches
kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.webhook\.github\.secret}' | base64 -d

# Fallback: increase poll interval if webhooks are unreliable
kubectl edit cm argocd-cm -n argocd
# Add: timeout.reconciliation: "30s"   (default 3m)
```

---

## 10. Summary

| Concept | ArgoCD Implementation |
|---------|----------------------|
| Git = source of truth | Application CRD points to repo path |
| Drift detection | application-controller compares live vs desired every 3 min |
| Auto-remediation | `selfHeal: true` reverts out-of-band changes |
| Deployment ordering | `argocd.argoproj.io/sync-wave` annotation |
| Multi-cluster rollout | ApplicationSet with cluster generator |
| NetworkPolicy health | Always "Healthy" — add custom Lua check |
| Progressive delivery | Argo Rollouts + VirtualService/HTTPRoute weights |
| Zero-trust bootstrap | Wave 0: default-deny → Wave 1: explicit allows → Wave 2: apps |
| ArgoCD self-protection | NetworkPolicy wave -1 allowing argocd namespace egress |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [ArgoCD — Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/) | Free | Official tutorial: install ArgoCD on minikube, create your first Application, watch GitOps sync — runs the full lesson flow |
| [Killercoda: ArgoCD Scenarios](https://killercoda.com/) | Free | Browser-based ArgoCD labs with pre-installed clusters — search "ArgoCD" in the Killercoda explore page |
| [ArgoCD Example Apps](https://github.com/argoproj/argocd-example-apps) | Free (GitHub) | Official sample applications including network-policy-heavy configurations; use as your Git repo target |
| [Codefresh: GitOps Fundamentals](https://codefresh.io/learn/argo-cd/) | Free course | Free ArgoCD fundamentals course from Codefresh (Argo maintainers) with hands-on exercises |

---

**Next:** [Lesson 34 — AI Platform Networking](34-ai-platform-networking.md)
