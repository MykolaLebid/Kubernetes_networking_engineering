# Lesson 22 — Multi-Cluster Networking

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 12 — Cilium](12-cilium-cni-ebpf.md), [Lesson 06 — BGP](06-bgp-fundamentals.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl with multiple contexts)
kubectl config get-contexts
kubectl config use-context <cluster-1>
kubectl get pods -A | head -10

# Terminal 2 — Mac (second cluster context)
kubectl config use-context <cluster-2>
cilium clustermesh status 2>/dev/null || echo "Cluster Mesh not enabled on this cluster"
kubectl get serviceimports -A 2>/dev/null || echo "MCS API not installed"
```

---

## Why This Matters

Production platforms often span multiple Kubernetes clusters — for high availability, regional proximity, workload isolation, or compliance. Multi-cluster networking solves the hardest problem: making services in different clusters discover and communicate with each other, securely and reliably.

---

## 1. Multi-Cluster Patterns

| Pattern | Description | Use Case |
|---------|-------------|---------|
| Flat network | Pod IPs routable across clusters | Same VPC, low latency |
| Gateway-based | Traffic goes through ingress/egress gateways | Different VPCs, encrypted |
| Service mirroring | Service objects mirrored across clusters | East-west service discovery |
| Cluster Mesh | Full interconnect with shared identity | Cilium native |
| DNS-based federation | DNS routes to nearest healthy cluster | Geo-distributed apps |

---

## 2. Multi-Cluster Services API (MCS)

The Kubernetes Multi-Cluster Services API (SIG-Multicluster) provides a standard for cross-cluster service export/import.

```yaml
# In cluster A — export a service
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: web
  namespace: default
---
# In cluster B — import it
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceImport
metadata:
  name: web
  namespace: default
spec:
  type: ClusterSetIP
  ports:
    - port: 80
      protocol: TCP
```

```bash
# DNS name for imported service:
# web.default.svc.clusterset.local
kubectl exec -it pod -- nslookup web.default.svc.clusterset.local
```

---

## 3. Cilium Cluster Mesh

Cilium's Cluster Mesh connects clusters so pods can communicate using their cluster-internal pod IPs and DNS names.

```bash
# Enable Cluster Mesh on cluster A
cilium clustermesh enable \
  --service-type LoadBalancer
cilium clustermesh status --wait

# Connect cluster B to cluster A
# (run with context pointing to cluster A)
cilium clustermesh connect \
  --destination-context cluster-b \
  --source-context cluster-a

# Verify mesh is connected
cilium clustermesh status
# Cluster A ←→ Cluster B  CONNECTED
```

```yaml
# Share a service globally (available in all mesh clusters)
apiVersion: v1
kind: Service
metadata:
  name: web
  annotations:
    service.cilium.io/global: "true"
    service.cilium.io/shared: "true"   # include this cluster's endpoints
spec:
  selector:
    app: web
  ports:
    - port: 80
```

```bash
# Global service load balances across all clusters
# Affinity to local cluster:
annotations:
  service.cilium.io/global: "true"
  service.cilium.io/affinity: "local"   # prefer local cluster, fall back cross-cluster
```

---

## 4. Istio Multi-Cluster

### Primary-Remote Model
One cluster has the control plane; remote clusters use it.

```bash
# Install Istio on primary cluster
istioctl install --set profile=default \
  --set values.pilot.env.EXTERNAL_ISTIOD=true

# Install remote cluster config
istioctl install --set profile=remote \
  --set values.global.remotePilotAddress=<primary-pilot-ip>
```

### Multi-Primary (Recommended for HA)
Each cluster runs its own Istiod.

```bash
# Step 1: Create a shared root CA
# (both clusters must trust the same root)

# Step 2: Install Istio on cluster 1
istioctl install -f cluster1.yaml

# Step 3: Install Istio on cluster 2
istioctl install -f cluster2.yaml

# Step 4: Cross-cluster east-west gateway
kubectl apply -n istio-system -f eastwest-gateway.yaml

# Step 5: Expose services for cross-cluster discovery
istioctl x create-remote-secret \
  --context=cluster1 \
  --name=cluster1 | kubectl apply --context=cluster2 -f -

# Services become reachable via their FQDN across clusters
```

---

## 5. Submariner

Submariner provides direct pod-to-pod connectivity between clusters using encrypted tunnels.

```bash
# Install subctl CLI
curl -Ls https://get.submariner.io | bash

# Deploy broker (coordinates cluster registration)
subctl deploy-broker --kubeconfig broker-cluster.kubeconfig

# Join cluster A
subctl join broker-info.subm --kubeconfig cluster-a.kubeconfig \
  --clusterid cluster-a \
  --natt-discovery-port 4900 \
  --globalnet   # if pod CIDRs overlap

# Join cluster B
subctl join broker-info.subm --kubeconfig cluster-b.kubeconfig \
  --clusterid cluster-b \
  --globalnet
```

```bash
# Verify connectivity
subctl verify --kubeconfig cluster-a.kubeconfig --toconfig cluster-b.kubeconfig

# Export service for cross-cluster access
subctl export service --namespace default web
# Creates ServiceExport → Lighthouse DNS resolves across clusters
```

Submariner topology:
```
Cluster A                   Cluster B
  Pod A ←→ Gateway ←→ [IPsec/WireGuard tunnel] ←→ Gateway ←→ Pod B
```

---

## 6. AWS Multi-Cluster (EKS)

```bash
# Option 1: VPC Peering — flat network, pod IPs routable
aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-cluster-a \
  --peer-vpc-id vpc-cluster-b

# Update route tables in both VPCs
aws ec2 create-route \
  --route-table-id rtb-xxxxxx \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id pcx-xxxxxx

# Option 2: AWS Transit Gateway — hub-and-spoke for many VPCs
aws ec2 attach-vpc-to-transit-gateway \
  --transit-gateway-id tgw-xxxxx \
  --vpc-id vpc-cluster-a

# Option 3: AWS VPC Lattice (new, service-level)
# Service-to-service connectivity without VPC peering
```

---

## 7. GCP Multi-Cluster (GKE)

```bash
# GKE Hub — register clusters to a fleet
gcloud container hub memberships register cluster-a \
  --gke-cluster us-central1/cluster-a

gcloud container hub memberships register cluster-b \
  --gke-cluster us-east1/cluster-b

# Enable Multi-Cluster Services
gcloud container hub multi-cluster-services enable

# Enable Multi-Cluster Ingress
gcloud container hub ingress enable \
  --config-membership=cluster-a

# MultiClusterIngress resource (deployed to config cluster)
apiVersion: networking.gke.io/v1
kind: MultiClusterIngress
metadata:
  name: web-ingress
spec:
  template:
    spec:
      backend:
        serviceName: web
        servicePort: 80
```

---

## 8. Overlapping Pod CIDRs Problem

When clusters have overlapping pod CIDRs (common in independent deployments), you need NAT or Globalnet.

```
Cluster A: pods 10.244.0.0/16
Cluster B: pods 10.244.0.0/16  ← SAME CIDR

Solution 1: Globalnet (Submariner)
  — Each cluster gets a unique global CIDR
  — Pods are SNATed to the global CIDR for cross-cluster traffic

Solution 2: Service-based communication only
  — Expose services, not pods — services have cluster-unique IPs

Solution 3: Re-IP pods (if possible)
  — Reinitialize clusters with non-overlapping CIDRs
```

---

## 9. Troubleshooting Multi-Cluster

```bash
# Cilium Cluster Mesh
cilium clustermesh status
# Check "Clusters" section for CONNECTED status

hubble observe --from-cluster cluster-b   # cross-cluster flows

# Istio
istioctl remote-clusters   # check registered remote clusters
istioctl proxy-config cluster <pod> | grep cluster-b

# Submariner
subctl show connections
subctl show endpoints
subctl diagnose all   # comprehensive health check

# DNS cross-cluster
# MCS: nslookup web.default.svc.clusterset.local
# Cilium: nslookup web.default.svc.cluster.local (global service)
# Submarine: nslookup web.default.svc.clusterset.local (Lighthouse)
```

---

## 10. Summary

| Solution | Mechanism | Pod-Level | Service-Level | Encryption |
|----------|-----------|-----------|--------------|------------|
| Cilium Cluster Mesh | eBPF + tunnels | Yes | Yes | WireGuard |
| Istio multi-cluster | Envoy gateways | Via mesh | Yes | mTLS |
| Submariner | IPsec/WireGuard tunnels | Yes | Via Lighthouse | IPsec/WG |
| MCS API | Standard API | No | Yes | Depends |
| VPC Peering (AWS/GCP) | Cloud routing | Yes | Yes | Optional |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Isovalent: Cilium Cluster Mesh](https://isovalent.com/labs/cilium-cluster-mesh/) | Free | Connect two Kubernetes clusters with Cilium Cluster Mesh, enable shared services, test cross-cluster pod connectivity |
| [Killercoda Playground](https://killercoda.com/) | Free | Multi-context kubectl setup; simulate multi-cluster with two separate namespaces |
| [Submariner Quickstart](https://submariner.io/getting-started/quickstart/) | Free | Official Submariner tutorial connecting two kind clusters — works locally without cloud |

---

**Next:** [Lesson 23 — Network Security Hardening](23-network-security-hardening.md)
