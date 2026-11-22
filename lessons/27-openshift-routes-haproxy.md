# Lesson 27 — OpenShift Routes and HAProxy Router

> **Track:** OpenShift Networking
> **Prerequisites:** [Lesson 17 — Ingress Controllers](17-ingress-controllers.md), [Lesson 25 — OpenShift Overview](25-openshift-networking-overview.md)
> **Duration:** ~2.5 hours

> **Goal:** Create edge, passthrough, and reencrypt Routes on OpenShift, configure a custom IngressController for router sharding, and read HAProxy backend stats to diagnose a 503 error.

---

## Practice Setup

```bash
# Terminal 1 — verify router is running and has an external IP
oc get pods -n openshift-ingress
oc get svc -n openshift-ingress router-default
# EXTERNAL-IP should be populated (NLB address or IP)

# Terminal 2 — inspect IngressController
oc get ingresscontroller default -n openshift-ingress-operator -o yaml \
  | grep -E "domain|replicas|endpointPublishing|conditions" | head -20

# Terminal 3 — peek at live HAProxy config inside the router
ROUTER=$(oc get pods -n openshift-ingress -o jsonpath='{.items[0].metadata.name}')
echo "Router pod: $ROUTER"
oc exec -n openshift-ingress $ROUTER -- \
  cat /var/lib/haproxy/conf/haproxy.config | head -60
```

> **See also:** [Lesson 17 — Ingress Controllers](17-ingress-controllers.md) for Kubernetes Ingress API comparison.
> **See also:** [Lesson 28 — OpenShift Egress](28-openshift-egress.md) for controlling outbound traffic from the same namespace.

---

## 1. Route vs Kubernetes Ingress

| Feature | OpenShift Route | Kubernetes Ingress |
|---------|----------------|-------------------|
| API group | `route.openshift.io/v1` | `networking.k8s.io/v1` |
| Controller | HAProxy Router | Any Ingress Controller |
| TLS passthrough | Native | Requires SNI-based annotation |
| TLS reencrypt | Native | Not standard |
| A/B weight splitting | Native (`alternateBackends`) | Controller-specific annotation |
| Wildcard host | Native | Via annotation |
| Admission status | Per-route `.status.ingress` | LB IP in `.status.loadBalancer` |
| Path-based routing | Yes | Yes |

---

## 2. Route Architecture

```mermaid
flowchart LR
    subgraph Client
        BR["Browser / Client"]
    end
    subgraph DNS
        WDNS["*.apps.cluster.example.com\n→ router EXTERNAL-IP"]
    end
    subgraph OpenShift
        SVC_LB["LoadBalancer Service\nrouter-default\n(NLB / MetalLB)"]
        subgraph IC["openshift-ingress namespace"]
            RP1["router-default-pod-1\nHAProxy"]
            RP2["router-default-pod-2\nHAProxy"]
        end
        subgraph App["application namespace"]
            SVC["Service\n(ClusterIP)"]
            POD1["Pod"]
            POD2["Pod"]
        end
        ROUTE["Route CR\nhost, TLS mode, weight"]
    end

    BR -- "HTTPS web.apps..." --> DNS
    DNS --> SVC_LB --> RP1
    SVC_LB --> RP2
    RP1 -- "watches / reconciles" --> ROUTE
    RP2 -- "watches / reconciles" --> ROUTE
    RP1 --> SVC --> POD1
    RP1 --> SVC --> POD2
```

---

## 3. The IngressController Operator

OpenShift manages routers via the `IngressController` CRD — never edit router pods directly.

```bash
# View the default IngressController
oc get ingresscontroller default -n openshift-ingress-operator -o yaml
# spec.domain: apps.cluster.example.com   <- wildcard DNS base
# spec.replicas: 2
# spec.endpointPublishingStrategy.type: LoadBalancerService
# status.conditions: Available True

# View router pods created by the operator
oc get pods -n openshift-ingress -o wide
# router-default-xxxxx-yyyyy   (one per replica, spread across infra nodes)

# View the LoadBalancer service (holds EXTERNAL-IP)
oc get svc -n openshift-ingress router-default

# Create a custom IngressController for internal traffic
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
      router: internal    # only routes in namespaces with this label
EOF
```

---

## 4. IngressController Configuration Reference

| Parameter | Default | Effect | When to change |
|-----------|---------|--------|---------------|
| `spec.replicas` | `2` | Number of HAProxy router pods | Increase for high throughput |
| `spec.domain` | cluster install value | Wildcard DNS base for auto-generated hostnames | Set at install; changing disrupts all routes |
| `endpointPublishingStrategy.type` | `LoadBalancerService` | How the router is exposed (LB, NodePort, HostNetwork) | Use `HostNetwork` on bare metal |
| `tuningOptions.maxConnections` | `50000` | HAProxy global maxconn | Increase for high-connection workloads |
| `tuningOptions.threadCount` | auto | HAProxy worker threads | Set to vCPU count of infra nodes |
| `httpHeaders.forwardedHeaderPolicy` | `Append` | Handling of `X-Forwarded-For` | Set `Replace` if upstream proxy already sets it |
| `logging.access.destination.type` | `Container` | Access log destination | Use `Syslog` for centralized logging |
| `routeAdmission.wildcardPolicy` | `WildcardsDisallowed` | Whether `*.example.com` routes are accepted | Set `WildcardsAllowed` for multi-tenant platforms |
| `routeAdmission.namespaceOwnership` | `InterNamespaceAllowed` | Whether routes can claim hostnames across namespaces | Set `Strict` for tenant isolation |

---

## 5. Route Types

### Edge — TLS terminates at the router

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
    insecureEdgeTerminationPolicy: Redirect   # HTTP → HTTPS 301
    # Optional: provide custom certificate
    # certificate: |-
    #   -----BEGIN CERTIFICATE-----
    # key: |-
    #   -----BEGIN RSA PRIVATE KEY-----
    # caCertificate: |-   (chain if needed)
```

### Passthrough — TLS goes all the way to the pod

```yaml
spec:
  tls:
    termination: passthrough
  # Router does NOT decrypt — routes by SNI hostname only
  # Cannot use path-based routing in passthrough mode
  # Pod must present a valid certificate
```

### Reencrypt — terminate at router, then re-establish TLS to pod

```yaml
spec:
  tls:
    termination: reencrypt
    destinationCACertificate: |-   # CA cert to verify the pod's server cert
      -----BEGIN CERTIFICATE-----
      ...
    # Optional: custom cert for the client-facing side
```

---

## 6. Route Lifecycle — Admission Sequence

```mermaid
sequenceDiagram
    participant U as User / CI
    participant API as API Server
    participant RO as Route Operator
    participant RP as Router Pod (HAProxy)

    U->>API: oc apply -f route.yaml
    API->>RO: Route created event
    RO->>RO: Validate hostname ownership<br/>Check routeAdmission policy
    RO->>API: Update route.status.ingress<br/>Admitted: True / False
    RP->>API: Watch Route objects (every 10s)
    RP->>RP: Regenerate haproxy.config<br/>Reload HAProxy (soft reload)
    Note over RP: HAProxy reload is zero-downtime:<br/>old process drains, new one takes over
```

```bash
# Check if a route was admitted
oc describe route web-edge | grep -A 15 "Status:"
# Ingress:
#   Host:  web.apps.cluster.example.com
#   Conditions:
#     Type: Admitted  Status: True
#     RouterName: default

# Check route admission across all routes
oc get routes -A -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.host,ADMITTED:.status.ingress[0].conditions[0].status'
```

---

## 7. Route Management Commands

```bash
# Expose a service as a route (auto-generates hostname from service name + domain)
oc expose svc web
# → web.apps.cluster.example.com

# Expose with explicit hostname
oc expose svc web --hostname=web.apps.cluster.example.com

# Create a TLS edge route with custom certificates
oc create route edge web-tls \
  --service=web \
  --hostname=web.apps.cluster.example.com \
  --cert=tls.crt \
  --key=tls.key

# View all routes across all namespaces
oc get routes -A

# Delete
oc delete route web-edge -n default
```

---

## 8. Weighted Routes — A/B Traffic Splitting

OpenShift Routes support native A/B splits — no service mesh required.

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

```bash
# Verify weights are reflected in HAProxy
oc exec -n openshift-ingress $ROUTER -- \
  grep -A5 "web.apps.cluster.example.com" /var/lib/haproxy/conf/haproxy.config \
  | grep "weight"
# server pod-v1-xxx 10.128.0.5:8080 weight 256  <- 80% → 256
# server pod-v2-xxx 10.128.0.6:8080 weight 64   <- 20% → 64
```

---

## 9. HAProxy Annotations

```yaml
metadata:
  annotations:
    # Connection timeouts
    haproxy.router.openshift.io/timeout: 60s
    haproxy.router.openshift.io/connect-timeout: 5s

    # Load balancing algorithm
    haproxy.router.openshift.io/balance: "leastconn"   # roundrobin, source, leastconn

    # Sticky sessions (source IP based)
    haproxy.router.openshift.io/balance: "source"

    # Rate limiting
    haproxy.router.openshift.io/rate-limit-connections: "true"
    haproxy.router.openshift.io/rate-limit-connections.rate-http: "100"

    # IP allowlist (space-separated CIDRs)
    haproxy.router.openshift.io/ip_whitelist: "192.168.1.0/24 10.0.0.1"

    # HTTP Strict Transport Security
    haproxy.router.openshift.io/hsts_header: "max-age=31536000;includeSubDomains;preload"

    # CORS
    haproxy.router.openshift.io/cors-allow-origin: "https://example.com"

    # Rewrite incoming request path
    haproxy.router.openshift.io/rewrite-target: /
```

---

## 10. IngressController Tuning

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
        type: Container    # stdout — scrape with Fluentd/Vector
      httpLogFormat: >-
        %ci:%cp [%t] %ft %b/%s %B %tsc %ac/%fc/%bc/%sc/%rc %{+Q}r
  httpHeaders:
    forwardedHeaderPolicy: Append
```

---

## 11. Router Sharding

Deploy multiple IngressControllers on different node groups, each serving different namespaces:

```bash
# Label namespace so the internal IngressController picks it up
oc label namespace my-app router=internal

# Confirm the internal router has admitted the route
oc describe route my-route -n my-app | grep RouterName
# RouterName: internal
```

---

## 12. Wildcard Routes

```bash
# Allow wildcard routes on the IngressController
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

## 13. Standard Kubernetes Ingress on OpenShift

OpenShift accepts standard Ingress resources — the router automatically converts them to Routes:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  annotations:
    route.openshift.io/termination: edge   # OpenShift TLS annotation
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

## Troubleshooting

| Symptom | Likely Cause | Diagnostic Command | Fix |
|---------|-------------|-------------------|-----|
| Route not admitted | Hostname claimed by another route / admission policy | `oc describe route <name> \| grep Conditions` | Check `routeAdmission.namespaceOwnership`; delete conflicting route |
| 503 Service Unavailable | No healthy pod endpoints behind service | `echo "show stat" \| socat - /var/lib/haproxy/run/haproxy.sock \| cut -d, -f1,2,18` | Check pod readiness probes; check service selector |
| Certificate error (browser) | Custom cert doesn't match hostname | `oc get route <name> -o jsonpath='{.spec.tls.certificate}' \| openssl x509 -noout -subject` | Re-create route with correct cert |
| No EXTERNAL-IP on router service | Cloud LB not provisioned / MetalLB missing | `oc get svc -n openshift-ingress router-default` | Check IngressController `endpointPublishingStrategy`; install MetalLB on bare metal |
| Route admitted but traffic returns 404 | Wrong `targetPort` or missing path in backend | `oc exec -n openshift-ingress $ROUTER -- curl -s http://<svc-ip>:<port>/path` | Verify service port and pod HTTP server path |
| HAProxy 502 Bad Gateway | Pod starts but not yet ready | `oc get endpoints <service>` — check address count | Add/tune readiness probe; check `haproxy.router.openshift.io/connect-timeout` |

```bash
# Check HAProxy backend health via UNIX socket
oc exec -n openshift-ingress $ROUTER -- \
  bash -c 'echo "show stat" | socat - /var/lib/haproxy/run/haproxy.sock | \
  cut -d, -f1,2,18,19 | grep -v "^#"'
# be_<namespace>_<service>_<port>,pod-name,UP,0  <- UP = healthy
# be_<namespace>_<service>_<port>,pod-name,DOWN,-- <- DOWN = no connection

# Check router log for 5xx errors
oc logs -n openshift-ingress $ROUTER | grep " 5[0-9][0-9] " | tail -20

# Test route from inside cluster (bypass DNS)
oc run -it --rm test --image=nicolaka/netshoot -- \
  curl -Hv "Host: web.apps.cluster.example.com" \
  http://router-default.openshift-ingress.svc

# Check all route status at once
oc get routes -A -o json \
  | jq '.items[] | select(.status.ingress[0].conditions[0].status != "True") | .metadata.name'
```

---

## Production Checklist

- [ ] At least 2 router replicas spread across infra nodes (`spec.replicas >= 2`)
- [ ] `maxConnections` tuned to expected peak concurrent connections per router pod
- [ ] All production routes use TLS (edge minimum; passthrough/reencrypt for mTLS)
- [ ] Custom certificates loaded for non-wildcard hostnames; wildcard cert for `*.apps.*`
- [ ] `routeAdmission.namespaceOwnership: Strict` for multi-tenant environments
- [ ] HAProxy access logs enabled and forwarded to centralized log aggregation
- [ ] IngressController `podDisruptionBudget` reviewed — router upgrades must not cause full outage

---

## Common Anti-Patterns

| What people do | Why it breaks | Correct approach |
|----------------|--------------|-----------------|
| Use passthrough TLS for a path-based route | HAProxy cannot inspect SNI beyond hostname — no path routing | Use reencrypt if path routing + TLS to pod is needed |
| Set `insecureEdgeTerminationPolicy: Allow` on public routes | Allows plain HTTP to production services — credentials in transit | Use `Redirect` or `None` on all production routes |
| Create routes directly instead of via IngressController | Router sharding and admission policies are bypassed | Always use `oc expose` or YAML; let the operator manage routing |
| Expect `X-Forwarded-For` to show real client IP without cloud LB proxy protocol | Cloud NLB replaces source IP unless proxy protocol or PROXY header is configured | Enable PROXY protocol on the NLB and set `httpHeaders.forwardedHeaderPolicy: Replace` |
| Ignore the `Admitted` condition | A route can exist but be silently unserved if the router rejects it | Monitor `oc get routes -A` and alert on `Admitted != True` |

---

## Quick Reference

| Use Case | Command |
|----------|---------|
| List all routes | `oc get routes -A` |
| Expose service as route | `oc expose svc <name> --hostname=<host>` |
| Check route admitted | `oc describe route <name> \| grep Admitted` |
| Create TLS edge route | `oc create route edge <name> --service=<svc> --cert=tls.crt --key=tls.key` |
| View IngressController | `oc get ingresscontroller -n openshift-ingress-operator -o yaml` |
| HAProxy backend stats | `echo "show stat" \| socat - /var/lib/haproxy/run/haproxy.sock` |
| View HAProxy config | `oc exec -n openshift-ingress $ROUTER -- cat /var/lib/haproxy/conf/haproxy.config` |
| Router logs (5xx only) | `oc logs -n openshift-ingress $ROUTER \| grep ' 5[0-9][0-9] '` |
| Enable wildcard routes | `oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p '{"spec":{"routeAdmission":{"wildcardPolicy":"WildcardsAllowed"}}}'` |
| Test route internally | `oc run --rm -it test --image=nicolaka/netshoot -- curl -H "Host: <host>" http://router-default.openshift-ingress.svc` |
| Scale router replicas | `oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p '{"spec":{"replicas":3}}'` |

---

## Summary

| Concept | Detail |
|---------|--------|
| Route CRD | `route.openshift.io/v1` — OpenShift's first-class Ingress equivalent |
| TLS modes | edge (terminate at router), passthrough (pod handles TLS), reencrypt (router re-encrypts to pod) |
| A/B routing | Native weight-based splitting via `alternateBackends` |
| IngressController | Operator-managed HAProxy deployment — `openshift-ingress-operator` |
| Wildcard DNS | `*.apps.cluster.example.com` — base domain set in IngressController `spec.domain` |
| Router sharding | Multiple IngressControllers with `namespaceSelector` / `routeSelector` for multi-tenant isolation |
| Standard Ingress | Also supported — auto-converted to Routes by the router |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) | Free 30-day cluster | Create Routes with edge/passthrough/reencrypt TLS; inspect HAProxy config; test weighted alternateBackends |
| [Red Hat Interactive Learning Portal](https://www.redhat.com/en/interactive-labs/openshift) | Free (Red Hat account) | Hands-on Route creation and IngressController configuration lab |

---

**Next:** [Lesson 28 — OpenShift EgressIP and EgressFirewall](28-openshift-egress.md)
