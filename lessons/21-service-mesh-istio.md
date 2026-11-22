# Lesson 21 — Service Mesh with Istio

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 12 — Services](13-kubernetes-services-kube-proxy.md), [Lesson 16 — Network Policies](16-network-policies.md)  
> **Duration:** ~3 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (istioctl + kubectl)
istioctl version 2>/dev/null || echo "Install: curl -L https://istio.io/downloadIstio | sh -"
kubectl get pods -n istio-system 2>/dev/null
istioctl proxy-status 2>/dev/null | head -10

# Terminal 2 — Mac
kubectl get peerauthentication -A 2>/dev/null
kubectl get authorizationpolicy -A 2>/dev/null
kubectl get virtualservice,destinationrule -A 2>/dev/null
```

---

## Why This Matters

A service mesh adds mTLS, observability, traffic management, and fault injection between services — without changing application code. Istio is the most feature-rich option. Understanding it lets you secure inter-service communication, implement progressive delivery, and get distributed tracing with zero application changes.

---

## 1. Architecture

### Sidecar Mode (classic Istio)
```
Pod
├── App container         (port 8080)
└── Envoy sidecar proxy   (intercepts all traffic via iptables)

Traffic flow:
  Caller Pod → Envoy → (mTLS) → Envoy → App Pod
                          ↑
                    Istiod provides certs, config
```

### Ambient Mode (sidecar-less, Istio 1.18+)
```
Node
├── ztunnel (per-node, L4 mTLS proxy)
└── waypoint proxy (per-namespace, L7 policy)

Traffic flow:
  Pod → ztunnel (L4 mTLS) → ztunnel → Pod
  (or) → waypoint proxy (L7 policy) →
```

Ambient mode eliminates sidecar overhead; ztunnel handles mTLS transparently.

```
Sidecar Injection + mTLS Handshake Flow

  kubectl apply pod.yaml
        │
        ▼
  API Server → MutatingWebhookConfiguration (istiod)
        │
        ▼
  Pod spec modified: inject envoy sidecar container
  + init container (iptables: redirect all traffic → envoy :15001)
        │
        ▼
  Pod running:
  ┌─────────────────────────────────────────────┐
  │  Pod A                                      │
  │  ┌────────────┐    ┌────────────────────┐   │
  │  │ App (8080) │◄──►│ Envoy sidecar      │   │
  │  │            │    │ :15001 (outbound)  │   │
  │  └────────────┘    │ :15006 (inbound)   │   │
  │                    └─────────┬──────────┘   │
  └──────────────────────────────┼──────────────┘
                                 │ mTLS (SPIFFE/X.509)
  ┌──────────────────────────────┼──────────────┐
  │  Pod B                       │              │
  │                    ┌─────────▼──────────┐   │
  │                    │ Envoy sidecar      │   │
  │                    │ :15006 (inbound)   │   │
  │  ┌────────────┐    │ :15001 (outbound)  │   │
  │  │ App (8080) │◄──►│                    │   │
  │  └────────────┘    └────────────────────┘   │
  └─────────────────────────────────────────────┘

mTLS handshake (SPIFFE/X.509 certificates from istiod CA):
  Envoy A presents: spiffe://cluster.local/ns/default/sa/frontend
  Envoy B validates against istiod-issued CA cert → trusts it
  Envoy B presents: spiffe://cluster.local/ns/default/sa/backend
  Envoy A validates → mutual trust established → TLS session begins
```

---

## 2. Installation

```bash
# Install Istio using istioctl
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-*/bin:$PATH

# Install with default profile
istioctl install --set profile=default -y

# Verify
istioctl verify-install
kubectl get pods -n istio-system

# Enable sidecar injection for a namespace
kubectl label namespace default istio-injection=enabled

# Check injection is working
kubectl get namespace default --show-labels
```

```bash
# Ambient mode installation
istioctl install --set profile=ambient -y
# No sidecar injection needed — ztunnel handles it per-node
kubectl label namespace default istio.io/dataplane-mode=ambient
```

---

## 3. mTLS with PeerAuthentication

```yaml
# Require mTLS for all services in a namespace
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT     # PERMISSIVE allows plain text too (migration period)
```

```bash
# Verify mTLS is active
istioctl authn tls-check <pod-name>.default
# HOST:PORT                                     STATUS     SERVER     CLIENT
# web.default.svc.cluster.local:80             OK         STRICT     STRICT

# Check certificate used
istioctl proxy-config secret <pod-name>.default
```

---

## 4. AuthorizationPolicy

```yaml
# Allow only specific services to call the web service
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: web-allow
  namespace: default
spec:
  selector:
    matchLabels:
      app: web
  action: ALLOW
  rules:
    - from:
        - source:
            principals:               # service account identity
              - "cluster.local/ns/default/sa/frontend"
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/*"]
---
# Default deny everything not explicitly allowed
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: default
spec:
  {}  # empty = deny all
```

---

## 5. Traffic Management

### VirtualService
```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: web
spec:
  hosts:
    - web
  http:
    # Canary: route 10% to v2
    - route:
        - destination:
            host: web
            subset: v1
          weight: 90
        - destination:
            host: web
            subset: v2
          weight: 10

    # Fault injection (testing resilience)
    - fault:
        delay:
          percentage:
            value: 10.0
          fixedDelay: 5s
        abort:
          percentage:
            value: 5.0
          httpStatus: 503
      route:
        - destination:
            host: web

    # Retry policy
    - retries:
        attempts: 3
        perTryTimeout: 2s
        retryOn: 5xx,reset,connect-failure
      timeout: 10s
      route:
        - destination:
            host: web
```

### DestinationRule
```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: web
spec:
  host: web
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http2MaxRequests: 1000
    outlierDetection:        # circuit breaker
      consecutiveGatewayErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

---

## 6. Ingress with Istio Gateway

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: web-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: web-tls-cert
      hosts:
        - web.example.com
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: web-vs
spec:
  hosts:
    - web.example.com
  gateways:
    - web-gateway
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: web
            port:
              number: 80
```

---

## 7. Observability

```bash
# Install Kiali (topology dashboard), Prometheus, Grafana, Jaeger
kubectl apply -f samples/addons/prometheus.yaml
kubectl apply -f samples/addons/grafana.yaml
kubectl apply -f samples/addons/jaeger.yaml
kubectl apply -f samples/addons/kiali.yaml

# Access Kiali (service mesh topology)
istioctl dashboard kiali

# Access Jaeger (distributed tracing)
istioctl dashboard jaeger

# Access Grafana (metrics)
istioctl dashboard grafana
```

```bash
# CLI observability
# Envoy access logs (per sidecar)
kubectl logs <pod> -c istio-proxy | head -20

# Proxy config dump
istioctl proxy-config cluster <pod>.default
istioctl proxy-config listener <pod>.default
istioctl proxy-config route <pod>.default

# Check for traffic issues
istioctl analyze   # validates Istio config
```

---

## 8. Bare Metal vs Cloud Considerations

### Bare Metal
```bash
# Istio ingressgateway needs an external IP
# Use MetalLB or NodePort:
kubectl patch svc istio-ingressgateway -n istio-system \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/type","value":"LoadBalancer"}]'
# MetalLB assigns the IP
```

### Cloud
```bash
# Cloud provisioner auto-assigns EXTERNAL-IP to ingressgateway Service
# AWS: becomes an NLB
# GKE: becomes a Passthrough NLB
kubectl get svc istio-ingressgateway -n istio-system
```

---

## 9. Troubleshooting Istio

```bash
# 1. Is sidecar injected?
kubectl describe pod <pod> | grep istio-proxy

# 2. Is Istiod healthy?
kubectl get pods -n istio-system
kubectl logs -n istio-system -l app=istiod | grep -E "WARN|ERROR"

# 3. Is mTLS the problem?
# Temporarily set PERMISSIVE mode
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: PERMISSIVE
EOF
# If traffic flows now → certificate or policy issue

# 4. Check Envoy configuration
istioctl proxy-config cluster <pod>.default | grep <service-name>

# 5. Enable Envoy access logging
kubectl apply -f - <<EOF
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: access-logging
spec:
  accessLogging:
    - providers:
        - name: envoy
EOF

# 6. Run connectivity test
istioctl experimental envoy-stats <pod>
```

---

## 10. Summary

| Feature | Istio Mechanism |
|---------|----------------|
| mTLS | Envoy sidecar intercepts all traffic, presents SPIFFE cert |
| AuthorizationPolicy | Envoy enforces at request time per-service |
| Traffic splitting | VirtualService weights |
| Circuit breaker | DestinationRule outlierDetection |
| Tracing | Envoy propagates B3/W3C trace headers |
| Ambient mode | ztunnel (L4) + waypoint (L7), no sidecar |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Istio — Get Started](https://istio.io/latest/docs/setup/getting-started/) | Free | Official Istio tutorial on minikube: deploy Bookinfo app, enable mTLS, configure VirtualService traffic splitting — covers this entire lesson |
| [Tetrate Academy: Istio Fundamentals](https://academy.tetrate.io/courses/istio-fundamentals) | Free (account required) | Official free Istio training with browser-based labs; covers PeerAuthentication, AuthorizationPolicy, DestinationRule |
| [Isovalent: TLS Visibility](https://isovalent.com/labs/tls-visibility/) | Free | Inspect TLS traffic and cipher identification using Cilium + Hubble — complements mTLS concepts |
| [Killercoda Playground](https://killercoda.com/) | Free | Run `istioctl proxy-status`, inspect sidecar config, test traffic routing |

---

**Next:** [Lesson 10 — eBPF and XDP in Kubernetes Networking](10-ebpf-xdp.md)
