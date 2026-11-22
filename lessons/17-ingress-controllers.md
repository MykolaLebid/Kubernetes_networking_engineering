# Lesson 17 — Ingress Controllers and L7 Load Balancing

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 13 — Kubernetes Services](13-kubernetes-services-kube-proxy.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

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

---

## Why This Matters

NodePort and LoadBalancer services give you L4 load balancing — they know TCP/UDP but nothing about HTTP. An Ingress controller adds L7 awareness: routing by hostname, URL path, TLS termination, authentication, rate limiting, and more. It's the standard way to expose HTTP workloads in both bare metal and cloud Kubernetes.

---

## 1. The Ingress Architecture

```
External Client
      │
      ▼
[Cloud LB or MetalLB VIP]
      │  (Service: LoadBalancer or NodePort)
      ▼
[Ingress Controller Pod]  ← NGINX, Traefik, Envoy, HAProxy...
      │  (reads Ingress objects via K8s API)
      │  routes by Host header / path
      ▼
[Backend Services + Pods]
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
# Install MetalLB (see Lesson 20)
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

---

## 8. Debugging Ingress

```bash
# 1. Does the Ingress controller have an external IP?
kubectl get svc -n ingress-nginx ingress-nginx-controller

# 2. Is the Ingress object correctly parsed?
kubectl describe ingress web-ingress

# 3. Are the backend services and pods healthy?
kubectl get endpoints api-service

# 4. Check NGINX config was generated correctly
kubectl exec -n ingress-nginx <controller-pod> -- \
  nginx -T | grep "server_name\|upstream\|proxy_pass"

# 5. Check NGINX access and error logs
kubectl logs -n ingress-nginx <controller-pod> --tail=100

# 6. Test connectivity
curl -v -H "Host: web.example.com" http://<controller-ip>:80
curl -vk https://web.example.com

# 7. Check certificate
openssl s_client -connect web.example.com:443 -servername web.example.com \
  < /dev/null 2>&1 | grep -E "subject|issuer|expire"
```

---

## 9. Summary

| Feature | Bare Metal | Cloud |
|---------|-----------|-------|
| External IP | MetalLB or NodePort | Cloud LB (auto) |
| TLS | cert-manager (LE or internal CA) | ACM/Cloud certificates |
| L7 LB | NGINX/Traefik/Envoy | ALB (AWS), GCE LB, App Gateway |
| Ingress class | Configure manually | Provided by cloud controller |
| Path routing | Standard across all | Standard across all |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Killercoda Playground](https://killercoda.com/) | Free | Deploy NGINX ingress controller, create Ingress resources, test path routing — full setup in a browser cluster |
| [Play with Kubernetes](https://labs.play-with-k8s.com/) | Free (Docker account) | Multi-node cluster in browser; deploy an ingress controller and expose services |
| [cert-manager: Getting Started](https://cert-manager.io/docs/getting-started/) | Free | Official tutorial deploying cert-manager on minikube with a self-signed issuer — matches the TLS section of this lesson |

---

**Next:** [Lesson 18 — Gateway API: Next-Generation Ingress](18-gateway-api.md)
