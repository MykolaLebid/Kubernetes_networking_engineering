# Networking Translation Cookbook: Every CF Primitive → K8s

> **Purpose:** Authoritative line-by-line mapping from every Cloud Foundry networking
> primitive to its Kubernetes / Kyma equivalent. Treat this as the canonical reference
> during a CF-to-K8s migration. Each section shows the original CF command or config
> snippet followed by the matching K8s YAML manifest.

---

## 1. Quick Read

| CF primitive | K8s equivalent | Key delta |
|---|---|---|
| `cf map-route app domain --hostname h` | Ingress / HTTPRoute | Declarative YAML; TLS handled by cert-manager |
| `cf map-route app apps.internal` | ClusterIP Service | CoreDNS resolves `svc.ns.svc.cluster.local` automatically |
| `cf add-network-policy src --destination-app dst` | NetworkPolicy (ingress + egress) | Label selectors replace app GUIDs |
| Security Group egress CIDR allow | NetworkPolicy egress ipBlock | Per-namespace; default-deny recommended |
| `--weight 20` on `cf map-route` | HTTPRoute `backendRefs[].weight` | Gateway API v1; Argo Rollouts for progressive delivery |
| TCP route on custom port | Gateway API TCPRoute | Listener per port on Gateway resource |
| CF Org + Space | Namespace | RBAC replaces UAA roles |
| Isolation segment (Diego Cell pool) | NodeSelector + Taint/Toleration | Node labels are the equivalent of segment names |
| `0.svc.apps.internal` BOSH-DNS | `pod-0.svc.ns.svc.cluster.local` StatefulSet DNS | Requires headless Service |
| CredHub `cf bind-service` | `envFrom.secretRef` or CSI Secret | External Secrets Operator bridges both worlds |
| Route service (inline proxy broker) | Istio EnvoyFilter / HTTPRoute filter | No broker; deploy filter as CRD |
| Gorouter health check (TCP/HTTP) | `readinessProbe` | Identical semantics; configure per container |
| Blue-green `cf map-route both` | HTTPRoute weights or Argo Rollouts | Native in Gateway API v1 |
| CF Canary (manual weight bumps) | Argo Rollouts canary steps | Automated analysis with Prometheus |
| CF Strangler Fig (route split) | HTTPRoute traffic split + incremental migration | Service-by-service; CF stays reachable throughout |
| SAP BTP CF env | Kyma environment (K8s runtime) | XSUAA token validation works in both |
| CF ASG → K8s node CIDRs | NetworkPolicy egress to node CIDR | Bidirectional rules required for coexistence |
| K8s → CF Gorouter | NetworkPolicy egress to Gorouter IP; Istio ServiceEntry | CF side unchanged |

**Migration mental model:**

1. CF Gorouter = K8s Ingress controller (or Gateway API).
2. CF C2C overlay network = K8s pod CIDR + NetworkPolicy.
3. CF Application Security Groups = NetworkPolicy egress ipBlock rules.
4. CF BOSH-DNS (`apps.internal`) = CoreDNS `svc.cluster.local`.
5. CF UAA / Org / Space RBAC = K8s RBAC on Namespaces.

---

## 2. Full Mapping Table

| # | CF concept | CF command / config | K8s resource | K8s field / annotation |
|---|---|---|---|---|
| 1 | External HTTP route | `cf map-route app example.com --hostname myapp` | `Ingress` | `spec.rules[].host: myapp.example.com` |
| 2 | External HTTPS route (auto TLS) | Gorouter wildcard cert | `cert-manager` Certificate + Ingress annotation | `cert-manager.io/cluster-issuer` |
| 3 | Internal route | `cf map-route app apps.internal --hostname svc` | `Service` (ClusterIP) | `spec.type: ClusterIP` |
| 4 | C2C allow policy | `cf add-network-policy src --destination-app dst --port 8080 --protocol tcp` | `NetworkPolicy` | `spec.ingress[].from[].podSelector` |
| 5 | C2C deny (default) | No ASG / no policy | NetworkPolicy default-deny | `spec.podSelector: {}` with no ingress rules |
| 6 | ASG egress CIDR allow | `"destination": "10.0.0.0/8", "ports": "443"` in security group JSON | `NetworkPolicy` egress | `spec.egress[].to[].ipBlock.cidr` |
| 7 | ASG egress DNS allow | Implicit for running apps | NetworkPolicy egress port 53 UDP+TCP | Explicit egress rule to `kube-dns` namespace |
| 8 | Route weight (blue-green) | `cf map-route v2 example.com --hostname app --weight 20` | `HTTPRoute` backendRefs weight | `backendRefs[].weight: 20` |
| 9 | TCP route | `cf create-route tcp.example.com --port 1234` | `Gateway` listener + `TCPRoute` | `Gateway.spec.listeners[].port: 1234` |
| 10 | Org / Space boundary | CF Org + Space hierarchy | `Namespace` | `metadata.namespace` |
| 11 | Isolation segment | Dedicated Diego Cell pool | `NodeSelector` + `Taint` + `Toleration` | `spec.nodeSelector`, `spec.tolerations` |
| 12 | apps.internal service DNS | `svc.apps.internal` BOSH-DNS | `svc.ns.svc.cluster.local` CoreDNS | `spec.clusterIP` auto-registered |
| 13 | Instance-level DNS | `0.svc.apps.internal` | `pod-0.svc.ns.svc.cluster.local` | Requires headless Service + StatefulSet |
| 14 | CredHub secret | `cf bind-service app svc` | `Secret` + `envFrom.secretRef` | or External Secrets Operator |
| 15 | Route service (inline proxy) | Service broker `cf bind-route-service` | Istio `EnvoyFilter` or `HTTPRoute` filter | CRD-based; no broker required |
| 16 | Gorouter health check | TCP/HTTP probe on 8080 | `readinessProbe` | `httpGet.path`, `tcpSocket.port` |
| 17 | Blue-green full swap | Map v2 route, unmap v1 | Update `HTTPRoute` to 100% new backend | Or Argo Rollouts `BlueGreen` strategy |
| 18 | Canary release | Incremental weight increase on route | Argo Rollouts `Canary` steps | Prometheus `AnalysisTemplate` |
| 19 | Strangler Fig pattern | Route-level traffic split | `HTTPRoute` with matching header or weight | Migrate service by service |
| 20 | SAP BTP CF to Kyma | Move workload from CF env to Kyma env | Kyma `APIRule` (wraps Istio VirtualService) | XSUAA JWT validation unchanged |
| 21 | Coexistence egress CF → K8s | ASG rule allowing K8s node CIDR | NetworkPolicy ingress from CF cell overlay CIDR | Bidirectional rules required |
| 22 | Coexistence egress K8s → CF | NetworkPolicy egress to Gorouter IP | No change on CF side (Gorouter is external) | Use Istio `ServiceEntry` for mesh traffic |
| 23 | Shared domain | `cf create-shared-domain` | `IngressClass` or Gateway `className` | Shared by namespace convention |
| 24 | Private domain | `cf create-private-domain` | Namespace-scoped `Gateway` | `spec.listeners[].allowedRoutes.namespaces` |

---

## 3. CF Routing → K8s Ingress / Gateway API

### 3.1 External HTTP route

**CF:**
```bash
cf map-route myapp example.com --hostname myapp
# Result: myapp.example.com → myapp containers via Gorouter
```

**K8s Ingress (nginx):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 8080
```

**K8s Gateway API HTTPRoute (preferred for new deployments):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp-route
  namespace: production
spec:
  parentRefs:
    - name: prod-gateway
      namespace: gateway-system
  hostnames:
    - myapp.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: myapp
          port: 8080
          weight: 100
```

### 3.2 Route weight / blue-green (Gateway API)

**CF:**
```bash
cf map-route myapp-v2 example.com --hostname myapp --weight 20
cf map-route myapp-v1 example.com --hostname myapp --weight 80
```

**K8s HTTPRoute with weights:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp-route
  namespace: production
spec:
  parentRefs:
    - name: prod-gateway
      namespace: gateway-system
  hostnames:
    - myapp.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: myapp-v1
          port: 8080
          weight: 80
        - name: myapp-v2
          port: 8080
          weight: 20
```

Increment `myapp-v2` weight gradually (20 → 50 → 100) using `kubectl patch` or Argo Rollouts.
Rollback: set `myapp-v1` back to `weight: 100` and remove `myapp-v2` backend ref.

### 3.3 TCP route

**CF:**
```bash
cf create-route tcp.example.com --port 5432
cf map-route mydb tcp.example.com --port 5432
```

**K8s Gateway + TCPRoute:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tcp-gateway
  namespace: gateway-system
spec:
  gatewayClassName: istio
  listeners:
    - name: tcp-5432
      protocol: TCP
      port: 5432
      allowedRoutes:
        kinds:
          - kind: TCPRoute
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TCPRoute
metadata:
  name: mydb-tcp
  namespace: production
spec:
  parentRefs:
    - name: tcp-gateway
      namespace: gateway-system
      sectionName: tcp-5432
  rules:
    - backendRefs:
        - name: mydb
          port: 5432
```

---

## 4. CF C2C Policy → K8s NetworkPolicy

### 4.1 C2C allow between two apps

**CF:**
```bash
cf add-network-policy frontend --destination-app backend --port 8080 --protocol tcp
```

**K8s — label pods and create NetworkPolicy:**
```yaml
# frontend pods carry label: app=frontend
# backend pods carry label: app=backend

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
```

### 4.2 Default-deny (equivalent of "no C2C policies")

**CF:** No network policy added = no C2C allowed (overlay is deny-by-default).

**K8s — apply default-deny to namespace:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

Apply this to every namespace before adding specific allow rules.

### 4.3 Mutual C2C (both directions)

**CF:**
```bash
cf add-network-policy svc-a --destination-app svc-b --port 9090 --protocol tcp
cf add-network-policy svc-b --destination-app svc-a --port 9090 --protocol tcp
```

**K8s — two NetworkPolicy objects, one per receiver:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-svc-b-from-svc-a
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: svc-b
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: svc-a
      ports:
        - protocol: TCP
          port: 9090
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-svc-a-from-svc-b
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: svc-a
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: svc-b
      ports:
        - protocol: TCP
          port: 9090
```

---

## 5. CF ASGs → K8s NetworkPolicy Egress

### 5.1 ASG allow egress to external CIDR

**CF security group JSON:**
```json
[
  {
    "protocol": "tcp",
    "destination": "10.20.0.0/16",
    "ports": "443",
    "description": "Allow HTTPS to on-prem"
  }
]
```
```bash
cf create-security-group allow-onprem allow-onprem.json
cf bind-security-group allow-onprem MyOrg MySpace
```

**K8s NetworkPolicy egress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-onprem-https
  namespace: production
spec:
  podSelector: {}       # applies to all pods in namespace
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 10.20.0.0/16
      ports:
        - protocol: TCP
          port: 443
```

### 5.2 ASG allow egress DNS (always required when default-deny is set)

**CF:** DNS egress is implicit for running apps.

**K8s — explicit DNS egress rule:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-dns
  namespace: production
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
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### 5.3 ASG allow multiple ports / internet egress

**CF:**
```json
[
  {"protocol": "tcp", "destination": "0.0.0.0/0", "ports": "80,443"}
]
```

**K8s — list ports in one egress rule with RFC-1918 exclusions:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-web
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 443
```

---

## 6. CF Service Discovery (apps.internal) → K8s DNS

### 6.1 Internal route for service-to-service calls

**CF:**
```bash
cf map-route backend apps.internal --hostname backend-svc
# Caller uses: http://backend-svc.apps.internal:8080
```

**K8s — ClusterIP Service (automatically registered in CoreDNS):**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: production
spec:
  selector:
    app: backend
  ports:
    - name: http
      protocol: TCP
      port: 8080
      targetPort: 8080
  type: ClusterIP
```

Callers inside the cluster use: `http://backend-svc.production.svc.cluster.local:8080`

Short form within the same namespace: `http://backend-svc:8080`

### 6.2 Instance-level addressing (0.svc.apps.internal)

**CF:**
```bash
# BOSH-DNS resolves individual app instances
# 0.backend-svc.apps.internal → instance 0
# 1.backend-svc.apps.internal → instance 1
```

**K8s — headless Service + StatefulSet:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: production
spec:
  selector:
    app: backend
  clusterIP: None          # headless — no VIP; DNS returns individual pod IPs
  ports:
    - port: 8080
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: backend
  namespace: production
spec:
  serviceName: backend-svc
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: myapp:latest
          ports:
            - containerPort: 8080
```

DNS names produced:
- `backend-0.backend-svc.production.svc.cluster.local`
- `backend-1.backend-svc.production.svc.cluster.local`
- `backend-2.backend-svc.production.svc.cluster.local`

### 6.3 Cross-namespace service discovery

**CF:** Cross-space C2C with network policy; DNS name stays `svc.apps.internal`.

**K8s — cross-namespace access with NetworkPolicy and FQDN:**
```yaml
# NetworkPolicy on the backend namespace to allow ingress from frontend namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-frontend-ns
  namespace: backend-ns
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: frontend-ns
      ports:
        - protocol: TCP
          port: 8080
```

Caller URL: `http://backend-svc.backend-ns.svc.cluster.local:8080`

---

## 7. CF Org / Space Isolation → K8s Namespaces + RBAC

### 7.1 Org / Space → Namespace mapping

**CF hierarchy:**
```
Org: acme-corp
  Space: production
  Space: staging
  Space: development
```

**K8s Namespace per space:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: acme-production
  labels:
    org: acme-corp
    space: production
    kubernetes.io/metadata.name: acme-production
---
apiVersion: v1
kind: Namespace
metadata:
  name: acme-staging
  labels:
    org: acme-corp
    space: staging
    kubernetes.io/metadata.name: acme-staging
```

### 7.2 CF Space Developer → K8s RBAC

**CF:**
```bash
cf set-space-role alice acme-corp production SpaceDeveloper
```

**K8s RoleBinding (built-in `edit` role):**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-developer
  namespace: acme-production
subjects:
  - kind: User
    name: alice@acme.com   # maps to OIDC claim
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit              # built-in: create/update/delete workloads
  apiGroup: rbac.authorization.k8s.io
```

### 7.3 CF Space Auditor → K8s view role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bob-auditor
  namespace: acme-production
subjects:
  - kind: User
    name: bob@acme.com
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

### 7.4 Isolation Segment → NodeSelector + Taint

**CF:**
```bash
cf create-isolation-segment gpu-nodes
cf enable-org-isolation acme-corp gpu-nodes
cf set-space-isolation-segment acme-ml-space gpu-nodes
```

**K8s — taint GPU nodes and add toleration + nodeSelector to workloads:**
```bash
kubectl taint nodes gpu-node-1 segment=gpu-nodes:NoSchedule
kubectl label nodes gpu-node-1 segment=gpu-nodes
```

```yaml
# In Deployment spec:
spec:
  template:
    spec:
      nodeSelector:
        segment: gpu-nodes
      tolerations:
        - key: segment
          operator: Equal
          value: gpu-nodes
          effect: NoSchedule
      containers:
        - name: ml-workload
          image: ml-trainer:latest
```

---

## 8. CF TLS (Gorouter) → K8s TLS (cert-manager + Ingress)

### 8.1 CF wildcard TLS (Gorouter handles everything)

In CF, Gorouter owns the wildcard cert for `*.example.com`; apps get TLS for free.

**K8s — cert-manager ClusterIssuer + per-Ingress Certificate:**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: production
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls-cert
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 8080
```

### 8.2 mTLS between services

**CF:** Envoy sidecar via CF service mesh or manual cert rotation.

**K8s with Istio — PeerAuthentication:**
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: mtls-strict
  namespace: production
spec:
  mtls:
    mode: STRICT
```

All pod-to-pod traffic within the namespace is mTLS; Istio manages cert rotation automatically.

### 8.3 Gorouter readiness → K8s readinessProbe

**CF:** Gorouter polls HTTP health endpoint before routing traffic to an instance.

**K8s:**
```yaml
spec:
  containers:
    - name: myapp
      image: myapp:latest
      ports:
        - containerPort: 8080
      readinessProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 10
        failureThreshold: 3
      livenessProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 15
        periodSeconds: 20
```

### 8.4 Coexistence: Istio ServiceEntry pointing at CF Gorouter

When K8s workloads in an Istio mesh need to call CF-hosted services, declare a ServiceEntry
so Istio routes and monitors the traffic correctly:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: cf-backend
  namespace: production
spec:
  hosts:
    - cf-backend.example.com
  ports:
    - number: 443
      name: https
      protocol: HTTPS
  resolution: DNS
  location: MESH_EXTERNAL
```

---

## 9. Production Checklist

### Networking

- [ ] Default-deny NetworkPolicy applied to all application namespaces
- [ ] Explicit ingress NetworkPolicy for each service-to-service path (replaces C2C policies)
- [ ] Egress NetworkPolicy rules cover all external dependencies (replaces ASGs)
- [ ] DNS egress rule present in every namespace using default-deny
- [ ] No pod runs without a `readinessProbe` (replaces Gorouter health check)
- [ ] TLS terminated at Ingress / Gateway; cert-manager `ClusterIssuer` validated
- [ ] mTLS enabled between internal services (Istio `PeerAuthentication: STRICT`)

### Routing

- [ ] All external hostnames have corresponding `Ingress` or `HTTPRoute`
- [ ] TCP routes migrated to Gateway API `TCPRoute` with matching `Gateway` listeners
- [ ] Blue-green weights sum to 100 in `HTTPRoute` `backendRefs`
- [ ] Canary `AnalysisTemplate` references valid Prometheus metrics
- [ ] `HTTPRoute` `hostnames` match DNS records (verify with `nslookup`)
- [ ] Rollback plan documented: CF route still active until 100% K8s confirmed stable

### Service discovery

- [ ] Every CF internal route (`apps.internal`) has a corresponding ClusterIP Service
- [ ] Instance-level addressing migrated to StatefulSet + headless Service
- [ ] Cross-namespace calls use FQDN (`svc.ns.svc.cluster.local`)

### Secrets

- [ ] All CredHub bindings replaced with K8s Secrets or External Secrets Operator
- [ ] No plaintext credentials in ConfigMaps or Deployment env vars
- [ ] Secret rotation process documented

### RBAC

- [ ] SpaceDeveloper → `edit` RoleBinding per namespace
- [ ] SpaceAuditor → `view` RoleBinding per namespace
- [ ] OrgManager → `admin` ClusterRoleBinding scoped to org namespaces
- [ ] No wildcard `*` rules in custom Roles

### Coexistence (hybrid phase)

- [ ] CF ASG rules allow egress to K8s node CIDR
- [ ] K8s NetworkPolicy allows ingress from CF cell overlay CIDR
- [ ] Istio `ServiceEntry` configured for CF-hosted services called from K8s
- [ ] Strangler Fig traffic weights logged and monitored
- [ ] Canary: start at 5% K8s (Gateway API HTTPRoute weight), monitor, increment to 20 / 50 / 100%
- [ ] Rollback: `cf map-route` back to 100% CF until K8s is confirmed stable

### SAP BTP / Kyma specific

- [ ] XSUAA issuer URL configured in `RequestAuthentication`
- [ ] `APIRule` created for each externally exposed service
- [ ] Kyma gateway class matches cluster gateway name
- [ ] CF environment ASG allows egress to Kyma cluster node CIDR
- [ ] Kyma NetworkPolicy allows ingress from CF cell overlay CIDR

---

## 10. See Also / Online Resources

- [Kubernetes NetworkPolicy docs](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Gateway API spec](https://gateway-api.sigs.k8s.io/)
- [cert-manager documentation](https://cert-manager.io/docs/)
- [Argo Rollouts — canary and blue-green](https://argoproj.github.io/argo-rollouts/)
- [Istio traffic management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Kyma APIRule reference](https://kyma-project.io/docs/kyma/latest/05-technical-reference/00-custom-resources/apix-02-apirule/)
- [External Secrets Operator](https://external-secrets.io/latest/)
- [CF C2C networking docs](https://docs.cloudfoundry.org/concepts/understand-cf-networking.html)
- [CF Application Security Groups](https://docs.cloudfoundry.org/concepts/asg.html)
- [SAP BTP Kyma environment overview](https://help.sap.com/docs/btp/sap-business-technology-platform/kyma-environment)

---

*Part of the CF Networking Course — see also:*
*[mig-01-strategy.md](mig-01-strategy.md) | [mig-03-coexistence-cutover.md](mig-03-coexistence-cutover.md)*
