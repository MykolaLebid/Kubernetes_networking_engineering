# Kubernetes Network Engineering — Manifests

Ready-to-apply YAML and shell files organized by lesson. Each file includes inline comments explaining what it does and any prerequisites.

## Usage

```bash
# Apply a YAML manifest
kubectl apply -f manifests/13/clusterip-service.yaml

# Apply to a specific namespace
kubectl apply -f manifests/16/default-deny-all.yaml -n my-namespace

# Run a shell script (requires root/sudo for network namespace operations)
sudo bash manifests/01/veth-bridge.sh
```

---

## Table of Contents

### Lesson 01 — Linux Networking

| File | Description |
|------|-------------|
| `01/veth-bridge.sh` | Creates a veth pair, Linux bridge, and two network namespaces to simulate pod-to-pod networking; includes connectivity test |

---

### Lesson 09 — CNI Spec

| File | Description |
|------|-------------|
| `09/10-bridge.conflist` | CNI conflist chaining bridge, portmap (DNAT), bandwidth limiting, and tuning plugins; drop into `/etc/cni/net.d/` |

---

### Lesson 13 — Services

| File | Description |
|------|-------------|
| `13/clusterip-service.yaml` | nginx Deployment + ClusterIP Service; accessible only from within the cluster via kube-proxy virtual IP |
| `13/nodeport-service.yaml` | NodePort Service exposing port 30080 on every node's IP; sets `externalTrafficPolicy: Local` to preserve source IP |
| `13/headless-service.yaml` | Headless Service (`clusterIP: None`) paired with a StatefulSet; DNS returns individual pod IPs |

---

### Lesson 14 — CoreDNS

| File | Description |
|------|-------------|
| `14/coredns-tuned-configmap.yaml` | CoreDNS ConfigMap with 30s cache TTL, stub zone for `corp.internal`, Prometheus metrics, and hot-reload enabled |
| `14/ndots-pod.yaml` | Pod with `dnsConfig` setting `ndots:1` to reduce DNS search-list round-trips for external FQDNs |

---

### Lesson 16 — NetworkPolicy

| File | Description |
|------|-------------|
| `16/default-deny-all.yaml` | Default-deny NetworkPolicy blocking all ingress and egress for every pod in a namespace |
| `16/allow-dns-egress.yaml` | Egress policy allowing pods to reach CoreDNS on UDP/TCP 53; always required alongside a default-deny |
| `16/frontend-to-backend.yaml` | Paired ingress+egress policies permitting `frontend` pods to reach `backend` pods on port 8080 |
| `16/allow-monitoring.yaml` | Ingress policy allowing Prometheus in the `monitoring` namespace to scrape pods on ports 9090 and 8080 |

---

### Lesson 17 — Ingress

| File | Description |
|------|-------------|
| `17/nginx-ingress.yaml` | Deployment + ClusterIP Service + Ingress with TLS termination and path-based routing via nginx Ingress controller |
| `17/cert-manager-issuer.yaml` | Let's Encrypt ClusterIssuers (staging + production) and a Certificate object for automated TLS via cert-manager |

---

### Lesson 18 — Gateway API

| File | Description |
|------|-------------|
| `18/gateway-class.yaml` | GatewayClass (Envoy Gateway controller) + Gateway with HTTP and HTTPS listeners; namespace-scoped route access control |
| `18/httproute-canary.yaml` | HTTPRoute implementing 90/10 weighted canary split with header-based override to force 100% canary |

---

### Lesson 19 — MetalLB

| File | Description |
|------|-------------|
| `19/ipaddresspool.yaml` | IPAddressPool defining an IP range for LoadBalancer Services + L2Advertisement for ARP-based announcement |
| `19/bgp-peer.yaml` | BGPPeer defining two ToR router peers (for ECMP redundancy) + BGPAdvertisement to publish VIPs via BGP |

---

### Lesson 21 — Istio

| File | Description |
|------|-------------|
| `21/peer-authentication-strict.yaml` | PeerAuthentication enforcing STRICT mTLS for all pods in a namespace; rejects plain-text traffic |
| `21/virtual-service-canary.yaml` | VirtualService routing 90% to `stable` subset and 10% to `canary` with header-based override and retry policy |
| `21/destination-rule.yaml` | DestinationRule defining `stable` and `canary` subsets with connection pool tuning and outlier detection |

---

### Lesson 23 — Network Security

| File | Description |
|------|-------------|
| `23/default-deny-all-namespaces.yaml` | Calico GlobalNetworkPolicy applying default-deny ingress+egress across the entire cluster (all namespaces) |
| `23/block-metadata-api.yaml` | NetworkPolicy (and Calico alternative) blocking pod egress to `169.254.169.254` to prevent cloud credential theft |

---

### Lesson 29 — AWS EKS

| File | Description |
|------|-------------|
| `29/eniconfig.yaml` | ENIConfig CRs for custom networking — maps each AZ to a secondary subnet and security group for pod ENIs |
| `29/sg-for-pods.yaml` | SecurityGroupPolicy assigning dedicated EC2 security groups to pods by label or service account selector |

---

### Lesson 33 — ArgoCD

| File | Description |
|------|-------------|
| `33/app-of-apps.yaml` | ArgoCD Application pointing to a Git directory of child Application manifests; uses automated sync with prune and self-heal |
| `33/sync-wave-example.yaml` | Multi-resource example using sync wave annotations to enforce apply order: namespace → CNI → NetworkPolicy → Deployment → Ingress |

---

## Prerequisites by Lesson

| Lesson | Prerequisites |
|--------|--------------|
| 01 | Root/sudo access, `iproute2` |
| 09 | CNI plugins installed on nodes (`/opt/cni/bin/`) |
| 13 | Any Kubernetes cluster |
| 14 | CoreDNS running in `kube-system` |
| 16 | CNI that supports NetworkPolicy (Calico, Cilium, Weave, etc.) |
| 17 | nginx Ingress controller; cert-manager (for `cert-manager-issuer.yaml`) |
| 18 | Gateway API CRDs; a supported Gateway controller (Envoy Gateway, Istio, nginx) |
| 19 | MetalLB installed; L2 or BGP connectivity from nodes to router |
| 21 | Istio installed; namespace labeled `istio-injection=enabled` |
| 23 | Calico CNI (for GlobalNetworkPolicy); standard Kubernetes for NetworkPolicy |
| 29 | EKS cluster; VPC CNI >= v1.11; `ENABLE_POD_ENI=true`; ENI-capable instance types |
| 33 | ArgoCD installed in `argocd` namespace |
