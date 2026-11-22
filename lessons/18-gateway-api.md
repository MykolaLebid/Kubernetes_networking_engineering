# Lesson 18 — Gateway API: Next-Generation Ingress

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 17 — Ingress Controllers](17-ingress-controllers.md)  
> **Duration:** ~2 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl)
# Check if Gateway API CRDs are installed
kubectl api-resources | grep -E "gateway|httproute|grpcroute|tcproute"
kubectl get gatewayclass 2>/dev/null || echo "Gateway API not installed — run: kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml"

# Terminal 2 — Mac
kubectl get gateway,httproute -A 2>/dev/null
```

---

## Why This Matters

The original Ingress API is minimal and forces complex configuration into opaque annotations. The Gateway API is its successor — a richer, role-oriented, and more expressive standard for traffic management. It is now GA in Kubernetes and is the future of ingress, service mesh, and multi-cluster routing.

---

## 1. Why Gateway API Replaces Ingress

| Limitation | Ingress API | Gateway API |
|-----------|-------------|-------------|
| Roles | No separation of concerns | Infrastructure, cluster, app teams separated |
| Cross-namespace routing | Not supported | Supported via ReferenceGrant |
| TCP/UDP routing | Not supported | TCPRoute, UDPRoute |
| gRPC routing | Not supported | GRPCRoute |
| Traffic splitting | Annotation hacks | Weight-based, natively in spec |
| Header modification | Annotation hacks | RequestHeaderModifier filter |
| Extensibility | Annotations (string blobs) | Extension points + custom filters |

---

## 2. Resource Hierarchy

```
GatewayClass (cluster-scoped)
     │  defines the controller (e.g., nginx, istio, envoy)
     ▼
Gateway (namespace-scoped)
     │  defines listeners (ports, protocols, TLS) and allowed routes
     ▼
HTTPRoute / TCPRoute / GRPCRoute / TLSRoute / UDPRoute
     │  defines routing rules → backend Services
     ▼
Service → Pods
```

---

## 3. GatewayClass

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx
spec:
  controllerName: k8s.io/ingress-nginx   # controller that manages this class
```

```bash
# Install NGINX Gateway Fabric (Gateway API implementation)
helm install nginx-gateway oci://ghcr.io/nginxinc/charts/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace

kubectl get gatewayclass
# NAME    CONTROLLER                    ACCEPTED
# nginx   k8s.io/ingress-nginx          True
```

---

## 4. Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-gateway
  namespace: infra
spec:
  gatewayClassName: nginx
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All      # or: Same | Selector
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: web-tls-cert
            namespace: infra
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: allowed
```

---

## 5. HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: default
spec:
  parentRefs:
    - name: prod-gateway
      namespace: infra
      sectionName: https     # bind to the https listener
  hostnames:
    - "web.example.com"
  rules:
    # Path-based routing
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-service
          port: 8080
          weight: 100

    # Header-based routing (canary)
    - matches:
        - headers:
            - name: X-Canary
              value: "true"
      backendRefs:
        - name: api-service-canary
          port: 8080

    # Traffic splitting (weighted)
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: frontend-v1
          port: 80
          weight: 90
        - name: frontend-v2
          port: 80
          weight: 10    # 10% canary traffic
```

---

## 6. HTTPRoute Filters

```yaml
rules:
  - filters:
      # Add/remove request headers
      - type: RequestHeaderModifier
        requestHeaderModifier:
          add:
            - name: X-Gateway-Version
              value: "v2"
          remove:
            - X-Internal-Token

      # Redirect HTTP to HTTPS
      - type: RequestRedirect
        requestRedirect:
          scheme: https
          statusCode: 301

      # URL rewrite
      - type: URLRewrite
        urlRewrite:
          path:
            type: ReplacePrefixMatch
            replacePrefixMatch: /v2

      # Mirror traffic to another service (for testing)
      - type: RequestMirror
        requestMirror:
          backendRef:
            name: shadow-service
            port: 8080
```

---

## 7. TCPRoute and GRPCRoute

```yaml
# TCPRoute — route raw TCP (databases, message queues)
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TCPRoute
metadata:
  name: postgres-route
spec:
  parentRefs:
    - name: prod-gateway
      sectionName: postgres   # listener on port 5432
  rules:
    - backendRefs:
        - name: postgres-service
          port: 5432
---
# GRPCRoute — route gRPC by service and method
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: grpc-route
spec:
  parentRefs:
    - name: prod-gateway
      sectionName: grpc
  rules:
    - matches:
        - method:
            service: "myapp.UserService"
            method: "GetUser"
      backendRefs:
        - name: user-service
          port: 50051
```

---

## 8. Cross-Namespace Routing with ReferenceGrant

```yaml
# HTTPRoute in namespace "app" references Service in namespace "shared"
# → requires ReferenceGrant in "shared" namespace

apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-from-app
  namespace: shared          # in the target namespace
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: app         # the source namespace
  to:
    - group: ""
      kind: Service
```

---

## 9. Gateway API on Cloud Providers

### AWS
The AWS Gateway API Controller maps Gateways to ALBs and VPC Lattice.
```bash
helm install aws-gateway-controller aws-gateway-api-controller \
  --namespace gateway-system
```

### GKE
GKE supports Gateway API natively with Cloud Load Balancers.
```yaml
# GKE GatewayClass
kubectl get gatewayclass
# gke-l7-global-external-managed    — global HTTPS LB
# gke-l7-regional-external-managed  — regional HTTPS LB
# gke-l7-rilb                       — internal LB
```

### AKS
```bash
# Enable Gateway API on AKS
az aks update --name my-aks --resource-group rg \
  --enable-azure-keyvault-secrets-provider
# App Gateway for Containers is AKS's Gateway API backend
```

---

## 10. Migrating from Ingress to Gateway API

```bash
# Step 1: Install CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Step 2: Install a Gateway API-compatible controller
# (most modern ingress controllers support both)

# Step 3: Create GatewayClass and Gateway

# Step 4: Translate Ingress to HTTPRoute
# Ingress:
#   host: web.example.com
#   path: /api → service: api:8080
# HTTPRoute:
#   parentRef: gateway
#   hostname: web.example.com
#   path: /api → backendRef: api:8080

# Step 5: Validate both coexist (Ingress and HTTPRoute can run in parallel)
kubectl get ingress,httproute
```

---

## 11. Summary

| Resource | Scope | Purpose |
|---------|-------|---------|
| GatewayClass | Cluster | Defines the controller implementation |
| Gateway | Namespace | Defines listeners (ports, protocols, TLS) |
| HTTPRoute | Namespace | HTTP/S routing rules → backends |
| TCPRoute | Namespace | TCP routing rules |
| GRPCRoute | Namespace | gRPC routing rules |
| ReferenceGrant | Namespace | Grants cross-namespace routing permission |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Isovalent: Cilium Gateway API + cert-manager](https://isovalent.com/labs/cilium-gateway-api-cert-manager/) | Free | HTTPS configuration and certificate management with Gateway API — interactive browser lab |
| [Isovalent: Advanced Gateway API Use Cases](https://isovalent.com/labs/advanced-gateway-api-use-cases/) | Free | Header rewriting, redirects, gRPC routing, and canary deployments with HTTPRoute |
| [Isovalent: Cilium Gateway API — External Authentication](https://isovalent.com/labs/cilium-gateway-api-external-authentication/) | Free | Implement auth at the gateway layer without modifying apps |
| [Gateway API — Getting Started](https://gateway-api.sigs.k8s.io/guides/) | Free | Official docs with hands-on examples — use with `kubectl apply` on minikube |

---

**Next:** [Lesson 17 — Load Balancing on Bare Metal: MetalLB and kube-vip](19-metallb-kube-vip.md)
