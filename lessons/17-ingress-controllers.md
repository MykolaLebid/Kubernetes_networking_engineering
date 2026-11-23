# Lesson 17 — Ingress Controllers and L7 Load Balancing

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 13 — Kubernetes Services](13-kubernetes-services-kube-proxy.md)  
> **Duration:** ~2.5 hours

> **Goal:** Deploy an NGINX or Traefik ingress controller, configure host-based and path-based routing with TLS termination via cert-manager, and diagnose 502/503/504 errors in the routing chain.



**Jump to:** [Theory](#theory) · [Practice](#practice) · [Troubleshooting](#troubleshooting) · [Production Checklist](#production-checklist) · [Quick Reference](#quick-reference) · [Check Your Understanding](#check-your-understanding)

---

## Theory

## 1. The Ingress Architecture

NodePort and LoadBalancer services give you L4 load balancing — they know TCP/UDP but nothing about HTTP. An Ingress controller adds L7 awareness: routing by hostname, URL path, TLS termination, authentication, rate limiting, and more.

```mermaid
flowchart LR
    Client["external client browser/curl"]
    LB["cloud LB or MetalLB VIP :80/:443 Service LoadBalancer"]
    IC["ingress-nginx controller pod :80/:443 namespace ingress-nginx"]
    API["Kubernetes API server :6443 watches Ingress objects"]
    SVC1["api-service :8080 ClusterIP"]
    SVC2["frontend-service :80 ClusterIP"]
    P1["api-pod-1 :8080"]
    P2["api-pod-2 :8080"]
    P3["frontend-pod :80"]
    TLS["cert-manager auto-renews TLS cert"]

    Client --"HTTPS :443"--> LB
    LB --"TCP :443 L4 forward"--> IC
    IC --"Host: web.example.com path: /api"--> SVC1
    IC --"Host: web.example.com path: /"--> SVC2
    SVC1 --"ClusterIP DNAT"--> P1
    SVC1 --"ClusterIP DNAT"--> P2
    SVC2 --"ClusterIP DNAT"--> P3
    API -."watch+sync Ingress rules".-> IC
    TLS -."inject TLS secret".-> IC
```

The Ingress controller is itself a Kubernetes application (Deployment + Service). It watches Ingress resources and programs its proxy configuration dynamically.

---

## 2. Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx        # which controller handles this
  tls:
    - hosts:
        - web.example.com
      secretName: web-tls-cert   # TLS certificate
  rules:
    - host: web.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 8080
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port:
                  number: 80
    - host: admin.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: admin-service
                port:
                  number: 80
```

### Key Parameters

| Parameter | Default | Effect | When to change |
|-----------|---------|--------|----------------|
| `ingressClassName` | (cluster default IngressClass) | Selects which controller processes this Ingress | Multiple controllers installed; set explicitly to avoid ambiguity |
| `pathType: Prefix` | — | Matches path and all sub-paths | Use `Exact` for precise path matching with no sub-path bleed |
| `pathType: Exact` | — | Matches only the exact path string | Strict API endpoints where sub-paths should 404 |
| `tls.secretName` | — | Secret containing `tls.crt` and `tls.key` | Required for HTTPS; pair with cert-manager for auto-renewal |
| `nginx.ingress.kubernetes.io/rewrite-target` | (no rewrite) | Rewrites URL before forwarding to backend | Strip path prefix before sending to backend service |
| `nginx.ingress.kubernetes.io/ssl-redirect` | `"true"` | Redirects HTTP to HTTPS | Set to `"false"` for plain HTTP environments |
| `nginx.ingress.kubernetes.io/proxy-body-size` | `"1m"` | Maximum request body size | Increase for file uploads (`"100m"`) |
| `nginx.ingress.kubernetes.io/affinity` | (none) | Enables sticky sessions via cookie | Use when backend has session state |

The request flow through the Ingress controller:

```mermaid
sequenceDiagram
    participant C as browser client
    participant LB as Cloud LB / MetalLB :443
    participant IC as ingress-nginx controller pod
    participant K8s as Kubernetes API (Ingress watch)
    participant SVC as api-service :8080 ClusterIP
    participant P as api-pod-1 :8080

    K8s-->>IC: Ingress update — new rule host=web.example.com path=/api
    IC-->>IC: regenerate nginx.conf upstream block api-service:8080

    C->>LB: HTTPS GET /api/v1/items (Host: web.example.com)
    LB->>IC: TCP :443 forward (SNI: web.example.com)
    IC->>IC: TLS termination with cert-manager certificate
    IC->>IC: match rule: host=web.example.com prefix /api → api-service:8080
    IC->>SVC: HTTP proxy_pass to api-service:8080 (X-Forwarded-For: client-ip)
    SVC->>P: ClusterIP DNAT to api-pod-1:8080
    P-->>SVC: HTTP 200 OK + JSON body
    SVC-->>IC: 200 OK response
    IC-->>C: 200 OK (adds X-Request-ID; strips internal headers)
```

---

## 3. NGINX Ingress Controller

The most widely used. Can run on bare metal or cloud.

```bash
# Install via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Verify
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Check EXTERNAL-IP — this is the IP your DNS should point to

# IngressClass resource
kubectl get ingressclass
```

```bash
# Bare metal: use NodePort or HostPort
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --set controller.service.type=NodePort \
  --set controller.hostPort.enabled=true  # bind port 80/443 on each node
```

### NGINX Annotations

```yaml
annotations:
  # Rate limiting
  nginx.ingress.kubernetes.io/limit-rps: "10"
  nginx.ingress.kubernetes.io/limit-connections: "5"

  # Timeouts
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "60"

  # Auth
  nginx.ingress.kubernetes.io/auth-type: basic
  nginx.ingress.kubernetes.io/auth-secret: basic-auth-secret

  # Redirect HTTP to HTTPS
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
  nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

  # Backend protocol
  nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"   # for HTTPS backends
  nginx.ingress.kubernetes.io/backend-protocol: "GRPC"    # for gRPC backends

  # Upload size
  nginx.ingress.kubernetes.io/proxy-body-size: "100m"

  # Sticky sessions
  nginx.ingress.kubernetes.io/affinity: "cookie"
  nginx.ingress.kubernetes.io/session-cookie-name: "INGRESSCOOKIE"
```

---

## 4. Traefik Ingress Controller

Popular in bare-metal and edge environments. Supports both Ingress and its own IngressRoute CRD.

```bash
# Install via Helm
helm repo add traefik https://helm.traefik.io/traefik
helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace
```

```yaml
# Traefik IngressRoute (more expressive than standard Ingress)
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: web-route
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: "Host(`web.example.com`) && PathPrefix(`/api`)"
      kind: Rule
      services:
        - name: api-service
          port: 8080
      middlewares:
        - name: rate-limit
  tls:
    certResolver: letsencrypt
```

---

## 5. TLS Termination and cert-manager

```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

```yaml
# ClusterIssuer for Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
---
# Ingress with automatic TLS certificate
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - web.example.com
      secretName: web-tls    # cert-manager will create this Secret
```

```bash
# Check certificate status
kubectl get certificate
kubectl describe certificate web-tls
kubectl get certificaterequest
```

---

## 6. Ingress on Bare Metal

The main challenge: no cloud LB to assign an EXTERNAL-IP.

### Option A: NodePort + DNS round-robin
```bash
# Service type NodePort — expose on every node
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

# DNS round-robin to all node IPs
# web.example.com → 192.168.1.10, 192.168.1.11, 192.168.1.12
```

### Option B: MetalLB + LoadBalancer
```bash
# Install MetalLB (see Lesson 19)
# Then service type=LoadBalancer works

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --set controller.service.type=LoadBalancer
# MetalLB assigns EXTERNAL-IP from pool
```

### Option C: HostPort (DaemonSet mode)
```yaml
# Runs NGINX on every node, bound to ports 80/443
controller:
  kind: DaemonSet
  hostPort:
    enabled: true
  service:
    type: ClusterIP   # no LB needed — traffic goes direct to node
```

---

## 7. Cloud Ingress Integration

### AWS — AWS Load Balancer Controller (ALB)
```yaml
# ALB Ingress (creates an Application Load Balancer)
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
```

### GKE — GCE Ingress Controller
```yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.global-static-ip-name: "my-static-ip"
```

### AKS — Application Gateway Ingress Controller (AGIC)
```yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
```

### Industry Applications

| Company / Project | Context | Technology from this lesson | Outcome |
|---|---|---|---|
| Cloudflare | Internal Kubernetes platform for distributed edge services | NGINX Ingress Controller with custom rate-limit and auth annotations | Centralized L7 routing for internal services without individual service-level proxies; zero per-service TLS config |
| Zalando (fashion e-commerce) | AWS-hosted Kubernetes serving millions of requests/day | AWS ALB Ingress Controller (AWS Load Balancer Controller) for path-based routing | Native AWS ALB integration; path-level traffic shaping between microservices without maintaining NGINX pods |
| GitHub | github.com global load balancing infrastructure | HAProxy-based ingress for github.com with custom health checks and routing | Sub-10ms routing decisions at scale; fine-grained backend health probing integrated with Kubernetes endpoints |
| Traefik Labs (open source maintainer) | Reference deployment for edge routing in Kubernetes | Traefik IngressRoute CRDs with Let's Encrypt auto-TLS via cert-manager | Zero-touch TLS certificate lifecycle; dynamic routing config from Kubernetes API without NGINX reload delays |

---

## Practice

### Environment Setup

```bash
# Terminal 1 — Mac (kubectl + minikube tunnel)
kubectl get ingress -A
kubectl get pods -n ingress-nginx 2>/dev/null || kubectl get pods -n kube-system | grep ingress

# To expose an Ingress locally (bare metal simulation):
minikube tunnel   # run in a dedicated terminal, requires sudo

# Terminal 2 — Mac
kubectl get svc -n ingress-nginx -o wide 2>/dev/null
curl -H "Host: myapp.local" http://$(minikube ip)/
```

Observation commands — run after deploying NGINX Ingress to see routing live:

```bash
# Watch the NGINX controller pod as Ingress objects are applied
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f &

# Deploy sample backends
kubectl create deployment web --image=nginx --port=80
kubectl expose deployment web --port=80
kubectl create deployment api --image=hashicorp/http-echo --port=5678 \
  -- /http-echo -text="api response"
kubectl expose deployment api --port=5678

# Apply and inspect routing
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: demo.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 5678
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
EOF

kubectl describe ingress demo                       # check rules and backend status
kubectl get endpoints web api                       # confirm pods are ready
curl -H "Host: demo.local" http://$(minikube ip)/  # expect: nginx HTML
curl -H "Host: demo.local" http://$(minikube ip)/api  # expect: "api response"
```

> **See also:** [Lesson 19 — MetalLB and kube-vip](19-metallb-kube-vip.md) for assigning the Ingress controller a real EXTERNAL-IP on bare metal.

### Hands-On Lab

**Step 1 — Install NGINX Ingress Controller and verify:**

```bash
# Install via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Verify controller is running and has an external IP
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
# NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
# ingress-nginx-controller   LoadBalancer   10.96.10.1      192.168.49.2    80:31080/TCP,443:31443/TCP

# Confirm IngressClass is registered
kubectl get ingressclass
# NAME    CONTROLLER                             PARAMETERS   AGE
# nginx   k8s.io/ingress-nginx                  <none>       1m
```

**Step 2 — Create host-based and path-based routing:**

```bash
# Deploy web and api backends (see Environment Setup above)
# Apply an Ingress with host-based routing and path prefix matching
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: web.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 5678
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
EOF

# Test routing with Host header
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H "Host: web.example.com" http://${INGRESS_IP}/       # expect: nginx HTML
curl -H "Host: web.example.com" http://${INGRESS_IP}/api    # expect: "api response"
```

**Step 3 — Inspect the generated nginx.conf:**

```bash
# View the full NGINX config generated from all Ingress rules
CONTROLLER_POD=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o name | head -1)
kubectl exec -n ingress-nginx ${CONTROLLER_POD} -- nginx -T | grep -A20 "server_name web.example.com"

# Tail access logs to see routing in action
kubectl logs -n ingress-nginx ${CONTROLLER_POD} --tail=20 -f
```

**Step 4 — Add TLS with cert-manager:**

```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# Check certificate status after adding TLS to your Ingress
kubectl get certificate -A
kubectl describe certificate web-tls

# Verify the TLS certificate from the command line
openssl s_client -connect web.example.com:443 -servername web.example.com < /dev/null 2>/dev/null | \
  openssl x509 -noout -subject -dates
```

### Configuration Reference

| Parameter | Default | Effect | When to Change |
|-----------|---------|--------|----------------|
| `ingressClassName` | Cluster default IngressClass | Selects which controller processes this Ingress | Always set explicitly when multiple controllers are installed |
| `pathType: Prefix` | — | Matches path and all sub-paths | Use `Exact` for precise path matching with no sub-path bleed |
| `pathType: Exact` | — | Matches only the exact path string | Strict API endpoints where sub-paths should 404 |
| `tls.secretName` | — | Secret containing `tls.crt` and `tls.key` | Required for HTTPS; pair with cert-manager for auto-renewal |
| `nginx.ingress.kubernetes.io/rewrite-target` | (no rewrite) | Rewrites URL before forwarding to backend | Strip path prefix before sending to backend service |
| `nginx.ingress.kubernetes.io/proxy-read-timeout` | 60 s | Max time to wait for backend response | Increase for slow backends; decrease to fail fast |
| `nginx.ingress.kubernetes.io/limit-rps` | (none) | Per-source-IP requests per second rate limit | Apply to all public-facing endpoints |
| `nginx.ingress.kubernetes.io/affinity` | (none) | Sticky sessions via cookie | Use when backend has in-memory session state |
| `nginx.ingress.kubernetes.io/proxy-body-size` | 1m | Maximum request body size | Increase to `100m` or `0` (unlimited) for file upload endpoints |
| controller `kind: DaemonSet` | Deployment | Runs NGINX pod on every node | Use on bare metal with HostPort so every node accepts traffic |

---

## Troubleshooting

| Symptom | Likely Cause | Diagnostic Command | Fix |
|---------|-------------|-------------------|-----|
| `EXTERNAL-IP: <pending>` on NGINX service | No cloud LB or MetalLB configured | `kubectl describe svc -n ingress-nginx ingress-nginx-controller` | On bare metal: install MetalLB (L19) or switch to NodePort |
| 502 Bad Gateway from NGINX | Backend pod not ready or port mismatch | `kubectl get endpoints <service>` and `kubectl logs -n ingress-nginx <controller>` | Check pod readiness, correct targetPort in Service spec |
| 503 Service Unavailable | No healthy backend endpoints | `kubectl get endpoints <service>` — look for empty `<none>` | Fix pod labels to match Service selector; check readinessProbe |
| 504 Gateway Timeout | Backend too slow or proxy-read-timeout too short | `kubectl exec -n ingress-nginx <pod> -- curl -v <backend>:port` | Increase `proxy-read-timeout` annotation; tune app performance |
| TLS certificate shows "Kubernetes Ingress Controller Fake Certificate" | cert-manager not running or ClusterIssuer not ready | `kubectl get clusterissuer; kubectl describe certificate <name>` | Fix ClusterIssuer ACME credentials; check cert-manager pod logs |
| `404 Not Found` from NGINX | Path or host does not match any Ingress rule | `kubectl describe ingress <name>` and check Rules section | Add correct host/path rule; verify `ingressClassName` |
| Admission webhook error on `kubectl apply` | NGINX admission webhook pod not ready | `kubectl get pods -n ingress-nginx` and check webhook pod status | Delete and recreate the ValidatingWebhookConfiguration if pod is healthy |

---

## Production Checklist

- [ ] `ingressClassName` explicitly set on every Ingress resource (do not rely on cluster default in multi-controller clusters)
- [ ] TLS configured for all public-facing Ingress resources; HTTP redirected to HTTPS via `ssl-redirect: "true"`
- [ ] cert-manager ClusterIssuer tested with a staging Let's Encrypt endpoint before switching to production
- [ ] Readiness probes on all backend pods so NGINX removes unhealthy endpoints automatically
- [ ] Rate limiting annotations (`limit-rps`, `limit-connections`) applied to public endpoints
- [ ] NGINX ConfigMap tuned for `worker-processes`, `keep-alive`, and `upstream-keepalive-connections` based on expected traffic
- [ ] Ingress controller Deployment or DaemonSet tested for rolling updates without dropping connections (minReadySeconds, PodDisruptionBudget)

---

## Common Anti-Patterns

| What people do | Why it breaks | Correct approach |
|----------------|--------------|-----------------|
| Use `ingressClassName: nginx` without verifying which IngressClass is installed | Multiple controllers (nginx + traefik) may both pick up or both ignore the resource depending on installed classes | Run `kubectl get ingressclass` to confirm the class name and controller before deploying Ingress objects |
| Skip TLS and rely on HTTP in production | Traffic between client and cluster is unencrypted; modern browsers block mixed content | Always terminate TLS at the ingress controller; use cert-manager for automatic certificate lifecycle |
| Reuse a single Ingress resource across many teams by adding annotation overrides | Annotations apply to the whole Ingress object; one team's rate-limit annotation affects all hosts in that object | Give each team or service its own Ingress resource; use `ingressClassName` to share one controller |
| Set `proxy-body-size: "0"` (unlimited) globally in the ConfigMap | Exposes the cluster to memory exhaustion from large request bodies | Set a reasonable default globally; override per-Ingress only for specific upload endpoints |
| Deploy NGINX in Deployment mode (not DaemonSet) on bare metal with HostPort | Only the nodes running NGINX pods receive traffic; other nodes are dead ends | Use DaemonSet + HostPort on bare metal so every node can accept traffic, or use MetalLB to route to only ready nodes |

---

## Quick Reference

| Use Case | Command |
|----------|---------|
| List all Ingress objects cluster-wide | `kubectl get ingress -A` |
| Describe an Ingress (rules, backends, TLS) | `kubectl describe ingress <name> -n <ns>` |
| Check NGINX controller external IP | `kubectl get svc -n ingress-nginx ingress-nginx-controller` |
| View generated nginx.conf | `kubectl exec -n ingress-nginx <pod> -- nginx -T` |
| Tail NGINX access and error logs | `kubectl logs -n ingress-nginx <pod> --tail=100 -f` |
| Test routing with a Host header | `curl -H "Host: web.example.com" http://<controller-ip>` |
| Check certificate status | `kubectl get certificate -A` |
| Describe a cert-manager Certificate | `kubectl describe certificate <name>` |
| Verify TLS certificate from CLI | `openssl s_client -connect web.example.com:443 -servername web.example.com < /dev/null` |
| Check backend endpoints | `kubectl get endpoints <service-name>` |
| Reload NGINX manually (graceful) | `kubectl exec -n ingress-nginx <pod> -- nginx -s reload` |
| List IngressClass resources | `kubectl get ingressclass` |

---

## Summary

| Feature | Bare Metal | Cloud |
|---------|-----------|-------|
| External IP | MetalLB or NodePort | Cloud LB (auto) |
| TLS | cert-manager (LE or internal CA) | ACM/Cloud certificates |
| L7 LB | NGINX/Traefik/Envoy | ALB (AWS), GCE LB, App Gateway |
| Ingress class | Configure manually | Provided by cloud controller |
| Path routing | Standard across all | Standard across all |

---

## Check Your Understanding

1. **[Concept question]** What is an `IngressClass` resource, and why must `ingressClassName` be explicitly specified on each Ingress object when multiple Ingress controllers are deployed in the same cluster?

   <details><summary>Answer</summary>

   An `IngressClass` is a cluster-scoped resource that maps a class name (e.g., `nginx`, `traefik`) to a specific Ingress controller. Each Ingress controller watches only for Ingress objects that reference its IngressClass. Without explicit `ingressClassName`, both controllers may try to process the same Ingress object — or neither will, if neither is configured as the default. Run `kubectl get ingressclass` to see installed classes and check the `ingressclass.kubernetes.io/is-default-class: "true"` annotation to identify the cluster default.

   </details>

2. **[Scenario question]** The NGINX Ingress controller returns a `502 Bad Gateway` error for a specific host/path rule. The Ingress object exists, the backend Service exists, and `kubectl get svc` shows the correct port. What is the most likely cause, and how do you confirm it?

   <details><summary>Answer</summary>

   A 502 means the NGINX controller reached the backend Service but got an error from the backend pod — most likely the pod is not ready, is crashing, or the Service's `targetPort` does not match the port the pod is actually listening on. Check `kubectl get endpoints <service-name>` to confirm pods are listed and their ports are correct. If endpoints show `<none>`, the pod selector in the Service does not match any pods. Check pod readiness with `kubectl get pods -l <selector> -o wide` and look at the READY column.

   </details>

3. **[Practical question]** What command would you run to view the full NGINX configuration that the ingress controller has generated from all deployed Ingress resources?

   <details><summary>Answer</summary>

   ```bash
   kubectl exec -n ingress-nginx <controller-pod> -- nginx -T
   ```
   This dumps the complete `nginx.conf` including all `server` blocks, `location` blocks, and upstream definitions generated from Ingress resources. It is the definitive way to verify that path rewrites, SSL settings, timeout annotations, and backend proxy targets are configured as expected.

   </details>

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Killercoda Playground](https://killercoda.com/) | Free | Deploy NGINX ingress controller, create Ingress resources, test path routing — full setup in a browser cluster |
| [Play with Kubernetes](https://labs.play-with-k8s.com/) | Free (Docker account) | Multi-node cluster in browser; deploy an ingress controller and expose services |
| [cert-manager: Getting Started](https://cert-manager.io/docs/getting-started/) | Free | Official tutorial deploying cert-manager on minikube with a self-signed issuer — matches the TLS section of this lesson |

---

**← Previous:** [Lesson 16 — Network Policies: Microsegmentation](16-network-policies.md)   |   **Next:** [Lesson 18 — Gateway API: Next-Generation Ingress](18-gateway-api.md)
