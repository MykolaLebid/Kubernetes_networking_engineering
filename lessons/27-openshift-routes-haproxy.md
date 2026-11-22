# Lesson 27 — OpenShift Routes and HAProxy Router

> **Track:** OpenShift Networking  
> **Prerequisites:** [Lesson 17 — Ingress Controllers](17-ingress-controllers.md), [Lesson 25 — OpenShift Overview](25-openshift-networking-overview.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — oc CLI
oc get routes -A
oc get ingresscontroller -n openshift-ingress-operator -o yaml | grep -A5 "domain\|replicas\|tlsSecurityProfile"

# Terminal 2 — oc
oc get pods -n openshift-ingress
oc rsh -n openshift-ingress deploy/router-default -- cat /var/lib/haproxy/conf/haproxy.config | head -40
```

---

## Why This Matters

OpenShift predates the Kubernetes Ingress API and introduced its own `Route` CRD. While OpenShift now also supports standard Ingress and Gateway API, Routes remain the primary way to expose HTTP/S workloads. The HAProxy-based router is the default implementation. Understanding Routes is essential for any OpenShift environment.

---

## 1. Route vs Ingress

| Feature | OpenShift Route | Kubernetes Ingress |
|---------|----------------|-------------------|
| API | `route.openshift.io/v1` | `networking.k8s.io/v1` |
| Controller | HAProxy Router | Any Ingress Controller |
| TLS termination | edge, passthrough, reencrypt | terminate only |
| Passthrough (no TLS decryption) | Yes | No (requires SNI-based routing) |
| Wildcard routes | Yes | Via annotation |
| Path-based routing | Yes | Yes |
| Weight-based routing | Yes (A/B) | Via annotation (controller-specific) |
| Status | Shows router assignments | Shows LB IP |

---

## 2. The IngressController (Router)

OpenShift manages routers via the `IngressController` CRD in `openshift-ingress-operator`:

```bash
# View the default IngressController
oc get ingresscontroller default -n openshift-ingress-operator -o yaml

# Key fields:
# spec.domain: apps.cluster.example.com   ← wildcard DNS base
# spec.replicas: 2
# spec.endpointPublishingStrategy.type: LoadBalancerService
# status.conditions: Available True

# View router pods
oc get pods -n openshift-ingress
# router-default-xxxxx-yyyyy

# View the router service (gets EXTERNAL-IP)
oc get svc -n openshift-ingress router-default
```

```bash
# Create a custom IngressController for a specific domain
oc apply -f - <<EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: internal
  namespace: openshift-ingress-operator
spec:
  domain: internal.cluster.example.com
  replicas: 2
  endpointPublishingStrategy:
    type: LoadBalancerService
    loadBalancer:
      scope: Internal     # Internal LB (AWS: internal NLB)
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra: ""
  namespaceSelector:
    matchLabels:
      router: internal
EOF
```

---

## 3. Route Types

### Edge (TLS terminated at router)
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: web-edge
  namespace: default
spec:
  host: web.apps.cluster.example.com
  to:
    kind: Service
    name: web
    weight: 100
  port:
    targetPort: 8080
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect   # HTTP → HTTPS
    # certificate: |-  (optional custom cert)
    # key: |-
    # caCertificate: |-
```

### Passthrough (TLS goes all the way to the pod)
```yaml
spec:
  tls:
    termination: passthrough
  # No certificate needed in the Route — pod handles TLS
  # Cannot do path-based routing in passthrough mode
```

### Re-encrypt (TLS terminated at router, then re-encrypted to pod)
```yaml
spec:
  tls:
    termination: reencrypt
    destinationCACertificate: |-   # CA to verify the pod's cert
      -----BEGIN CERTIFICATE-----
      ...
```

---

## 4. Route Management

```bash
# Create a route from a service (simplest way)
oc expose svc web --hostname=web.apps.cluster.example.com

# Create a TLS edge route
oc create route edge web-tls \
  --service=web \
  --hostname=web.apps.cluster.example.com \
  --cert=tls.crt \
  --key=tls.key

# View all routes
oc get routes -A

# Check route status (is it admitted by a router?)
oc describe route web-edge
# Status:
#   Ingress:
#     Host:  web.apps.cluster.example.com
#     Conditions:
#       Type: Admitted  Status: True   ← router picked it up
#       Router: default

# Delete a route
oc delete route web-edge
```

---

## 5. Weighted Routes (A/B Traffic Splitting)

OpenShift Routes natively support weighted traffic splitting between services — no service mesh needed.

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: web-ab
spec:
  host: web.apps.cluster.example.com
  to:
    kind: Service
    name: web-v1
    weight: 80          # 80% to v1
  alternateBackends:
    - kind: Service
      name: web-v2
      weight: 20        # 20% to v2
  port:
    targetPort: 8080
  tls:
    termination: edge
```

---

## 6. HAProxy Router Configuration

The HAProxy router is configured via environment variables and annotations.

```bash
# View HAProxy config inside the router pod
oc exec -n openshift-ingress router-default-xxxxx -- \
  cat /var/lib/haproxy/conf/haproxy.config | head -50

# Key HAProxy annotations on a Route:
```

```yaml
metadata:
  annotations:
    # Timeouts
    haproxy.router.openshift.io/timeout: 60s
    haproxy.router.openshift.io/connect-timeout: 5s

    # Rate limiting (requires HAProxy rate-limit module)
    haproxy.router.openshift.io/rate-limit-connections: "true"
    haproxy.router.openshift.io/rate-limit-connections.rate-http: "100"

    # Sticky sessions
    haproxy.router.openshift.io/balance: "source"   # or roundrobin, leastconn

    # IP whitelisting
    haproxy.router.openshift.io/ip_whitelist: "192.168.1.0/24 10.0.0.1"

    # HTTP strict transport security
    haproxy.router.openshift.io/hsts_header: "max-age=31536000;includeSubDomains;preload"

    # CORS
    haproxy.router.openshift.io/cors-allow-origin: "https://example.com"

    # Rewrite target
    haproxy.router.openshift.io/rewrite-target: /
```

---

## 7. IngressController Tuning

```yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  replicas: 3
  tuningOptions:
    headerBufferBytes: 32768
    headerBufferMaxRewriteBytes: 8192
    maxConnections: 50000
    threadCount: 4
  logging:
    access:
      destination:
        type: Container    # log to stdout
      httpLogFormat: >-
        %ci:%cp [%t] %ft %b/%s %B %tsc %ac/%fc/%bc/%sc/%rc %{+Q}r
  httpHeaders:
    forwardedHeaderPolicy: Append   # X-Forwarded-For handling
```

---

## 8. Wildcard Routes

```bash
# Enable wildcard routes on an IngressController
oc patch ingresscontroller default \
  -n openshift-ingress-operator \
  --type=merge \
  -p '{"spec":{"routeAdmission":{"wildcardPolicy":"WildcardsAllowed"}}}'

# Create a wildcard route
oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: wildcard-route
spec:
  host: "*.apps.cluster.example.com"
  wildcardPolicy: Subdomain
  to:
    kind: Service
    name: web
  tls:
    termination: edge
EOF
```

---

## 9. Standard Ingress on OpenShift

OpenShift also accepts standard Kubernetes Ingress resources — the router handles them.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  annotations:
    route.openshift.io/termination: edge   # OpenShift-specific annotation
spec:
  ingressClassName: openshift-default
  rules:
    - host: web.apps.cluster.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

---

## 10. Troubleshooting Routes

```bash
# 1. Is the route admitted?
oc describe route web-edge | grep -A10 "Status"

# 2. Check router logs
oc logs -n openshift-ingress router-default-xxxxx | tail -50

# 3. Is the router pod running?
oc get pods -n openshift-ingress

# 4. Does the router service have an EXTERNAL-IP?
oc get svc -n openshift-ingress router-default

# 5. Test route from inside the cluster
oc run -it --rm test --image=nicolaka/netshoot -- \
  curl -Hv "Host: web.apps.cluster.example.com" http://router-default.openshift-ingress.svc

# 6. Check HAProxy backend health
oc exec -n openshift-ingress router-default-xxxxx -- \
  bash -c 'echo "show stat" | socat - /var/lib/haproxy/run/haproxy.sock | \
  cut -d, -f1,2,18,19 | grep -v "^#"'

# Common issues:
# 1. Route not admitted → check routeAdmission policy, namespace selector
# 2. 503 Service Unavailable → no healthy pod endpoints
# 3. Certificate errors → cert doesn't match hostname
# 4. No EXTERNAL-IP on router service → need MetalLB or cloud LB
```

---

## 11. Summary

| Concept | Detail |
|---------|--------|
| Route CRD | `route.openshift.io/v1` — OpenShift's Ingress equivalent |
| TLS modes | edge (terminate at router), passthrough, reencrypt |
| A/B routing | Native weight-based splitting via alternateBackends |
| IngressController | Manages HAProxy router deployment and configuration |
| Annotations | HAProxy-specific tuning per Route |
| Standard Ingress | Also supported — converted to Routes by the router |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) | Free 30-day cluster | Create Routes with edge/passthrough/reencrypt TLS; inspect HAProxy config; test weighted alternateBackends |
| [Red Hat Interactive Learning Portal](https://www.redhat.com/en/interactive-labs/openshift) | Free (Red Hat account) | Hands-on Route creation and IngressController configuration lab |

---

**Next:** [Lesson 28 — OpenShift EgressIP and EgressFirewall](28-openshift-egress.md)
