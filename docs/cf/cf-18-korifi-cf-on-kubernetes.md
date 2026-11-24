# Lesson CF-18: Korifi — Cloud Foundry API on Kubernetes

**Track:** CF-F — Advanced CF Networking and Modern Runtimes
**Prerequisites:** CF-01 (Architecture), CF-05 (Silk CNI), CF-10 (C2C Policies), CF-15 (BOSH DNS)

---

## Quick Read (10 min)

**Core idea:** Korifi is the Cloud Foundry V3 API running natively on Kubernetes. It translates `cf push` into Kubernetes-native objects — no Diego, no Gorouter, no BOSH. Same developer experience, entirely different control plane.

**What stays the same:**
- `cf push`, `cf routes`, `cf network-policies` — identical CLI workflow
- Space isolation, org quotas, buildpack lifecycle
- CF V3 API surface (apps, routes, builds, spaces, orgs)

**What changes underneath:**

| CF / BOSH component | Korifi equivalent |
|---|---|
| Diego Cell (rep + executor) | Kubernetes Pod (kpack build + standard workload) |
| Gorouter | Contour (Envoy-based ingress) |
| Silk CNI + VXLAN overlay | Standard K8s CNI (Calico/Cilium) + NetworkPolicy |
| VXLAN Policy Agent | Native K8s NetworkPolicy objects |
| Route Emitter / NATS | Korifi route controller + HTTPProxy CRD |
| BOSH DNS apps.internal | CoreDNS (standard cluster DNS) |
| UAA | External OIDC provider (Dex or existing IdP) |
| CF API (Cloud Controller) | Korifi API server (CRD-backed) |

**Key CRDs introduced by Korifi:**

```
CFApp        — represents a pushed application
CFBuild      — a single build (like cf v3-build)
CFPackage    — source code / Docker image reference
CFRoute      — a mapped route (host + domain + path)
CFSpace      — a CF space → K8s namespace
CFOrg        — a CF org → K8s namespace
CFDomain     — a shared or private domain
CFServiceBinding — binds a service instance to an app
```

**Quick architecture diagram:**

```mermaid
graph TD
    CLI["cf CLI / CF API client"]
    KorifiAPI["Korifi API server\n(CF V3 REST)"]
    etcd["etcd\n(K8s state store)"]
    kpack["kpack\nbuildpack runner"]
    Contour["Contour\n(Envoy ingress)"]
    CoreDNS["CoreDNS"]
    NP["K8s NetworkPolicy\n(CNI-enforced)"]
    Pod["App Pod\n(K8s workload)"]

    CLI -->|HTTPS CF V3| KorifiAPI
    KorifiAPI -->|CRD writes| etcd
    KorifiAPI -->|CFBuild → Image| kpack
    KorifiAPI -->|CFRoute → HTTPProxy| Contour
    kpack -->|push image| Pod
    Contour -->|route traffic| Pod
    NP -->|allow/deny| Pod
    CoreDNS -->|resolve| Pod
```

**Key networking differences from BOSH-CF:**
- No VXLAN overlay — apps run on the same flat K8s pod network
- No SNAT at the Diego Cell boundary — pods have routable cluster IPs
- No NATS-based route registration — Contour HTTPProxy objects are declarative
- No `bosh ssh` needed to debug — `kubectl exec` and `kubectl logs` work
- ASGs replaced by K8s NetworkPolicy — same intent, native primitives
- Route TTLs gone — routes are CRD objects; they persist until deleted

**What you gain:** full `kubectl` observability, GitOps-ready, Helm-installable, standard K8s RBAC, Prometheus/Grafana native metrics, no BOSH director dependency.

**What you lose (for now):** TCP Router equivalent, full service broker ecosystem parity, some advanced Gorouter features (sticky sessions via JSESSIONID).

---

## Deep Dive

---

## Practice Setup

You need two terminals for this lesson.

**Terminal 1 — Korifi cluster (kubectl)**

```bash
# Verify Korifi is installed
kubectl get pods -n korifi
kubectl get crds | grep cloudfoundry.org

# Check Korifi API server is reachable
kubectl get svc -n korifi korifi-api-svc

# Point cf CLI at the Korifi API endpoint
cf api https://localhost:9000 --skip-ssl-validation
cf auth admin
cf target -o my-org -s my-space
```

**Terminal 2 — cf CLI (developer workflow)**

```bash
# Standard cf CLI — same commands as BOSH-CF
cf apps
cf routes
cf network-policies
cf push my-app -p ./app --no-start
cf env my-app
cf logs my-app --recent
```

> You can install Korifi locally with kind + cert-manager + kpack in under 15 minutes. The Korifi quickstart script handles the full stack.

```bash
# Local kind cluster quickstart (reference — takes ~10 min)
kind create cluster --name korifi
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
# Then follow https://github.com/cloudfoundry/korifi/blob/main/INSTALL.md
```

---

## 1. Architecture — CF API on Kubernetes

### From BOSH to CRDs

Traditional CF has a monolithic Cloud Controller that owns a PostgreSQL database with its entire state. Korifi replaces this with Kubernetes CRDs — the K8s API server becomes the state store, and controllers implement the reconciliation loops that Cloud Controller used to run as background workers.

```mermaid
graph LR
    subgraph "BOSH CF (traditional)"
        CC["Cloud Controller\n(Ruby/Rails)"]
        CCDB["CC Database\n(PostgreSQL)"]
        Diego["Diego (BBS + Cells)"]
        GR["Gorouter"]
        NATS["NATS bus"]
        CC --> CCDB
        CC --> Diego
        Diego -->|register route| NATS
        NATS --> GR
    end

    subgraph "Korifi (K8s native)"
        KorifiAPI2["Korifi API\n(Go)"]
        etcd2["etcd\n(CRDs as state)"]
        Controllers["Korifi Controllers\n(reconcile loops)"]
        kpack2["kpack\n(builds)"]
        Contour2["Contour\n(ingress)"]
        KorifiAPI2 --> etcd2
        etcd2 -->|watch| Controllers
        Controllers --> kpack2
        Controllers --> Contour2
    end
```

> **K8s Engineer's Translation:** Cloud Controller + its PostgreSQL database = `kube-apiserver` + etcd. All CF state is now a standard `kubectl get` away. The Diego scheduling loop = Kubernetes scheduler + kpack controller. Gorouter = Contour with HTTPProxy objects. NATS route registration = controller writing an HTTPProxy CRD.

### The CF V3 API surface

Korifi implements the CF V3 API exactly. From a developer's perspective, `cf push` works identically:

```bash
# This command works unchanged against Korifi
cf push hello-world \
  -b go_buildpack \
  -m 128M \
  -k 1G \
  --health-check-type http \
  --health-check-http-endpoint /health
```

Internally, Korifi translates this into:

1. A `CFPackage` object with the source code reference
2. A `CFBuild` object triggering kpack
3. A `CFApp` object with the desired state
4. A `CFRoute` object for the default route
5. A Kubernetes `Deployment` and `Service` for the actual workload

```bash
# See the K8s objects behind a cf push
kubectl get cfapp -n cf-space-my-space
kubectl get cfroute -n cf-space-my-space
kubectl get cfbuild -n cf-space-my-space
kubectl get deployment -n cf-space-my-space
```

### Namespace mapping

Korifi maps the CF hierarchy directly to Kubernetes namespaces:

```
CF Org  my-org        → K8s namespace  cf-org-my-org
CF Space my-space     → K8s namespace  cf-space-my-space (child of cf-org-my-org)
CF App  my-app        → K8s Deployment in cf-space-my-space
```

```bash
# List all CF-related namespaces
kubectl get namespaces | grep cf-

# Inspect a CF space namespace
kubectl describe namespace cf-space-my-space

# See RBAC for CF space
kubectl get rolebindings -n cf-space-my-space
```

> **K8s Engineer's Translation:** CF orgs and spaces = Kubernetes namespaces with hierarchical RBAC. CF space developer role = a RoleBinding granting Kubernetes RBAC inside that namespace. This means you can use standard K8s `kubectl auth can-i` to debug CF permission issues.

---

## 2. Networking — Routes, Ingress, and Service Discovery

### Contour replaces Gorouter

In BOSH CF, Gorouter maintains an in-memory routing table refreshed via NATS every 20 seconds. In Korifi, routing is declarative: each `cf map-route` creates or updates a `CFRoute` CRD, which the Korifi route controller translates into a Contour `HTTPProxy` object.

```bash
# Map a route (identical cf CLI syntax)
cf map-route my-app apps.example.com --hostname my-app

# What Korifi creates under the hood
kubectl get cfroute -n cf-space-my-space
kubectl get httpproxy -n cf-space-my-space

# Example CFRoute object
kubectl get cfroute my-app-route -n cf-space-my-space -o yaml
```

Example `CFRoute` object:

```yaml
apiVersion: korifi.cloudfoundry.org/v1alpha1
kind: CFRoute
metadata:
  name: my-app-route
  namespace: cf-space-my-space
spec:
  host: my-app
  path: ""
  protocol: http
  domainRef:
    name: apps-example-com
    namespace: cf-root-namespace
  destinations:
    - appRef:
        name: my-app-guid
      port: 8080
      protocol: http
      weight: 100
```

The Korifi route controller reconciles this into a Contour `HTTPProxy`:

```yaml
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: my-app-route
  namespace: cf-space-my-space
spec:
  virtualhost:
    fqdn: my-app.apps.example.com
    tls:
      secretName: korifi-workloads-ingress-cert
  routes:
    - conditions:
        - prefix: /
      services:
        - name: my-app-svc
          port: 8080
```

> **K8s Engineer's Translation:** `cf map-route` = creating a Kubernetes `Ingress` or `HTTPProxy` resource. No TTLs, no heartbeating, no NATS — routes are durable CRD objects. Removing a route is `cf unmap-route`, which deletes the HTTPProxy. Contour watches these and programs Envoy proxy pods accordingly.

### Network policies — K8s native

BOSH CF uses VXLAN overlay + VXLAN Policy Agent to implement C2C policies as iptables rules on Diego Cells. Korifi uses standard Kubernetes `NetworkPolicy` objects enforced by whatever CNI is installed (Calico, Cilium, etc.).

```bash
# CF CLI syntax unchanged
cf add-network-policy frontend --destination-app backend --port 8080 --protocol tcp

# Korifi translates this into a K8s NetworkPolicy
kubectl get networkpolicy -n cf-space-my-space

# Inspect the generated policy
kubectl get networkpolicy backend-from-frontend -n cf-space-my-space -o yaml
```

Generated `NetworkPolicy`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-from-frontend-8080-tcp
  namespace: cf-space-my-space
  labels:
    korifi.cloudfoundry.org/source-app-guid: frontend-guid
    korifi.cloudfoundry.org/dest-app-guid: backend-guid
spec:
  podSelector:
    matchLabels:
      korifi.cloudfoundry.org/app-guid: backend-guid
  ingress:
    - from:
        - podSelector:
            matchLabels:
              korifi.cloudfoundry.org/app-guid: frontend-guid
      ports:
        - protocol: TCP
          port: 8080
  policyTypes:
    - Ingress
```

> **K8s Engineer's Translation:** `cf add-network-policy` = `kubectl apply -f networkpolicy.yaml`. The policy is a standard K8s NetworkPolicy — you can inspect it with `kubectl`, write Kyverno policies against it, audit it with Falco, etc. No separate Policy Server process needed.

### Service discovery — CoreDNS replaces BOSH DNS

BOSH CF uses a custom BOSH DNS health-aware resolver. Apps in the same space can reach each other via `<app-name>.apps.internal`. Korifi uses standard CoreDNS.

```bash
# In BOSH CF — works in Korifi too via compatibility shim
curl http://backend.apps.internal:8080/health

# In Korifi — apps also get standard K8s service DNS
# Format: <service-name>.<namespace>.svc.cluster.local
curl http://my-app-svc.cf-space-my-space.svc.cluster.local:8080
```

The Korifi app controller creates a standard Kubernetes `Service` for each `CFApp`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-svc
  namespace: cf-space-my-space
  labels:
    korifi.cloudfoundry.org/app-guid: my-app-guid
spec:
  selector:
    korifi.cloudfoundry.org/app-guid: my-app-guid
  ports:
    - port: 8080
      targetPort: 8080
  type: ClusterIP
```

> **K8s Engineer's Translation:** BOSH DNS `apps.internal` = standard CoreDNS `svc.cluster.local`. Each CF app = one K8s Service. Cross-app communication via service DNS is a first-class concept in both worlds. The main difference: no health-aware client-side LB (you rely on the standard K8s endpoint controller + readiness probes instead).

---

## 3. Build Pipeline — kpack Replaces Diego Staging

### From staging cells to kpack

In BOSH CF, buildpack staging runs on a dedicated Diego Cell: a container is launched, the buildpack detect/compile/release cycle runs, and a droplet (tgz) is produced and stored in the blobstore. Diego then launches app containers from that droplet.

Korifi replaces this entirely with kpack, which implements the Cloud Native Buildpacks (CNB) spec. The output is an OCI image pushed to a container registry — not a droplet. App workloads run standard Kubernetes pods pulling from that registry.

```bash
# Trigger a build (happens automatically on cf push)
cf v3-create-build <app-guid>

# Watch the build progress
cf v3-get-build <build-guid>

# Equivalent kubectl view
kubectl get cfbuild -n cf-space-my-space
kubectl get taskrun -n cf-space-my-space   # kpack uses Tekton TaskRuns internally

# Watch build logs (replaces cf logs --recent for staging)
kubectl logs -n cf-space-my-space -l image.kpack.io/build=1 -c build
```

### Environment variables and app lifecycle

```bash
# Set env vars — identical syntax
cf set-env my-app DATABASE_URL "postgres://user:pass@host:5432/db"
cf restage my-app

# What Korifi does: updates the CFApp spec, kpack rebuilds
kubectl get cfapp my-app-guid -n cf-space-my-space -o yaml | grep -A 20 env

# Scale an app — identical syntax
cf scale my-app -i 3 -m 256M

# Korifi updates the Deployment replicas and resource limits
kubectl get deployment -n cf-space-my-space -l korifi.cloudfoundry.org/app-guid=my-app-guid
```

### Image registry configuration

Korifi requires a container registry for storing built images. This is configured at install time:

```yaml
# From korifi-controllers-config ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: korifi-controllers-config
  namespace: korifi
data:
  config.yaml: |
    containerRegistrySecretNames:
      - image-registry-credentials
    workloadImageBuilderName: kpack-image-builder
    maxRetainedBuildsPerApp: 5
    maxRetainedPackagesPerApp: 5
    taskTTL: 30d
    builderReadinessTimeout: 25s
```

```bash
# Check which registry Korifi is using
kubectl get configmap korifi-controllers-config -n korifi -o yaml

# Inspect the image pull secret for app namespaces
kubectl get secret image-registry-credentials -n cf-space-my-space -o yaml
```

> **K8s Engineer's Translation:** CF droplet = OCI container image in a registry. CF staging cell = kpack `Image` resource + a Tekton `TaskRun`. The kpack lifecycle is fully observable via `kubectl get image`, `kubectl get build`, and standard pod logs — far more transparent than BOSH CF staging.

---

## 4. AI Working Group — Korifi for AI/GPU Workloads (June 2026)

### Background

The CF AI Working Group published its first guidance in June 2026, addressing how Korifi can serve AI and ML workloads in addition to traditional 12-factor apps. The core challenge: AI workloads need GPU node scheduling, large model artifact storage, and high-bandwidth pod-to-pod networking — none of which were considered in the original CF developer-experience model.

The working group's position is that Korifi's K8s-native architecture makes these extensions tractable in a way that BOSH CF never could support: GPU taints/tolerations, ResourceQuotas for GPU resource types, and high-performance CNI configurations (Cilium eBPF bypass, SR-IOV) are standard K8s primitives that compose naturally with Korifi's CRD model.

```mermaid
graph TD
    subgraph "CF Developer Experience (unchanged)"
        CFpush["cf push my-model-server\n--no-start"]
        CFenv["cf set-env my-model-server\nMODEL_PATH /models/llama3"]
        CFstart["cf start my-model-server"]
        CFpush --> CFenv --> CFstart
    end

    subgraph "Korifi AI Extensions (June 2026 WG)"
        CFApp2["CFApp\n(annotated for GPU)"]
        KorifiCtrl["Korifi AI controller\n(WG proposal)"]
        GPUNode["K8s GPU Node\n(nvidia.com/gpu taint)"]
        ModelPVC["PVC — model weights\n(ReadOnlyMany)"]
        HPA["HPA / KEDA\n(queue-depth scaling)"]

        CFApp2 -->|reconcile| KorifiCtrl
        KorifiCtrl -->|toleration + nodeSelector| GPUNode
        KorifiCtrl -->|volumeMount| ModelPVC
        KorifiCtrl -->|ScaledObject| HPA
    end

    CFstart --> CFApp2
```

> **K8s Engineer's Translation:** The CF developer says `cf push`. The Korifi AI controller reads CF annotations and injects the K8s-native concerns (GPU tolerations, PVC mounts, KEDA ScaledObjects) that the developer should not need to know about. Same CF UX on top of full K8s GPU scheduling.

### GPU scheduling via CFApp annotations (WG proposal)

The working group proposes extending `CFApp` with an `ai` section in the spec to express GPU requirements without exposing raw K8s scheduling primitives to CF developers:

```yaml
apiVersion: korifi.cloudfoundry.org/v1alpha1
kind: CFApp
metadata:
  name: llama3-inference
  namespace: cf-space-ai-team
  annotations:
    korifi.cloudfoundry.org/ai-workload: "true"
spec:
  displayName: llama3-inference
  desiredState: STARTED
  lifecycle:
    type: docker
    data:
      image: my-registry/llama3-server:latest
  ai:
    gpuResourceType: nvidia.com/gpu
    gpuCount: 1
    modelStorageClaimName: llama3-weights-pvc
    modelMountPath: /models
```

The Korifi AI controller translates this into a standard K8s `Deployment` with:

```yaml
# Generated by Korifi AI controller
spec:
  template:
    spec:
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
      nodeSelector:
        accelerator: nvidia-gpu
      containers:
        - name: app
          resources:
            limits:
              nvidia.com/gpu: "1"
          volumeMounts:
            - name: model-weights
              mountPath: /models
              readOnly: true
      volumes:
        - name: model-weights
          persistentVolumeClaim:
            claimName: llama3-weights-pvc
            readOnly: true
```

```bash
# CF developer workflow — GPU-aware cf push
cf push llama3-inference --docker-image my-registry/llama3-server:latest --no-start
cf set-env llama3-inference GPU_COUNT 1
cf set-env llama3-inference MODEL_PATH /models/llama3

# Apply AI annotations via CF API v3 (WG extension)
cf curl /v3/apps/$(cf app llama3-inference --guid) \
  -X PATCH \
  -d '{"metadata":{"annotations":{"korifi.cloudfoundry.org/ai-workload":"true","korifi.cloudfoundry.org/gpu-count":"1"}}}'

cf start llama3-inference

# Verify GPU pod was scheduled on the right node
kubectl get pod -n cf-space-ai-team -l korifi.cloudfoundry.org/app-guid=$(cf app llama3-inference --guid) \
  -o jsonpath='{.items[0].spec.nodeName}'
```

### High-bandwidth networking for AI workloads

GPU workloads doing distributed training (data parallel, tensor parallel) require high-bandwidth pod-to-pod networking. The WG recommends:

1. **Cilium eBPF datapath** — eliminates iptables overhead; critical for all-reduce collective operations between model replicas
2. **SR-IOV for InfiniBand/RoCE** — for clusters with high-speed fabrics; requires device plugin and CNI chaining
3. **Whereabouts IPAM** — for deterministic pod IP assignment needed by distributed training frameworks (PyTorch DDP, DeepSpeed)

```bash
# Check if Cilium eBPF bypass is enabled (recommended for AI workloads)
kubectl exec -n kube-system <cilium-pod> -- cilium status | grep "BPF datapath"

# Check pod-to-pod bandwidth between two AI app pods
kubectl exec -n cf-space-ai-team <frontend-pod> -- \
  iperf3 -c <backend-pod-ip> -t 10 -P 4

# For SR-IOV: check VF allocation on GPU nodes
kubectl get node <gpu-node> -o jsonpath='{.status.allocatable}' | jq 'with_entries(select(.key | contains("sriov")))'
```

### Korifi C2C policy for AI service mesh (WG guidance)

AI inference services often follow a pattern: gateway pod → model server → embedding service. The WG recommends expressing this as CF C2C policies, which Korifi translates to K8s NetworkPolicy:

```bash
# Allow API gateway to reach model server
cf add-network-policy api-gateway --destination-app llama3-inference \
  --port 8080 --protocol tcp

# Allow model server to reach embedding service
cf add-network-policy llama3-inference --destination-app embedding-svc \
  --port 8081 --protocol tcp

# Deny all other C2C traffic (default in Korifi — explicit for documentation)
# No command needed — NetworkPolicy default-deny is applied at namespace level

# Verify the resulting NetworkPolicy chain
kubectl get networkpolicy -n cf-space-ai-team
```

```bash
# Check bandwidth and latency for model inference path
kubectl exec -n cf-space-ai-team <gateway-pod> -- \
  curl -w "@/dev/stdin" -o /dev/null -s http://<model-server-pod-ip>:8080/v1/completions \
  <<EOF
    time_namelookup: %{time_namelookup}\n
    time_connect: %{time_connect}\n
    time_total: %{time_total}\n
EOF
```

> **K8s Engineer's Translation:** The June 2026 AI Working Group positions Korifi as a CF-UX wrapper over standard K8s GPU scheduling and high-performance networking. CF developers do not write `tolerations` or `nodeSelector` — they annotate their `CFApp`. Platform engineers configure the underlying K8s primitives. This is the same separation of concerns CF has always offered, now extended to AI infrastructure.

---

## 5. Troubleshooting

### Korifi-specific failure modes

**Problem: `cf push` succeeds but app never starts**

```bash
# Check CFApp desired/actual state
kubectl get cfapp -n cf-space-my-space -o wide
kubectl describe cfapp <app-guid> -n cf-space-my-space

# Check the underlying Deployment
kubectl get deployment -n cf-space-my-space
kubectl describe deployment <app-guid> -n cf-space-my-space

# Check pod status
kubectl get pods -n cf-space-my-space -l korifi.cloudfoundry.org/app-guid=<app-guid>
kubectl describe pod <pod-name> -n cf-space-my-space

# Common cause: image pull failure — check registry credentials
kubectl get events -n cf-space-my-space --sort-by=.lastTimestamp | tail -20
```

**Problem: Route not resolving — `cf push` completes but app returns 503**

```bash
# Check CFRoute status
kubectl get cfroute -n cf-space-my-space
kubectl describe cfroute <route-name> -n cf-space-my-space

# Check Contour HTTPProxy
kubectl get httpproxy -n cf-space-my-space
kubectl describe httpproxy <proxy-name> -n cf-space-my-space

# Check Contour Envoy logs
kubectl logs -n projectcontour -l app=envoy --tail=50

# Verify Service endpoints
kubectl get endpoints -n cf-space-my-space

# Check if pods are Ready (Contour only routes to Ready pods)
kubectl get pods -n cf-space-my-space -o wide
```

**Problem: C2C policy not working — app cannot reach another app**

```bash
# Verify NetworkPolicy was created
kubectl get networkpolicy -n cf-space-my-space
kubectl describe networkpolicy <policy-name> -n cf-space-my-space

# Check pod labels match the policy selectors
kubectl get pod <pod-name> -n cf-space-my-space --show-labels

# Test connectivity directly (bypass routes)
kubectl exec -n cf-space-my-space <frontend-pod> -- \
  curl -v http://<backend-pod-ip>:8080/health

# Check CNI is enforcing NetworkPolicy (depends on CNI)
# For Calico:
kubectl get globalnetworkpolicy
# For Cilium:
kubectl exec -n kube-system <cilium-pod> -- cilium policy get
```

**Problem: Build failing — `cf push` shows staging error**

```bash
# Check CFBuild status
kubectl get cfbuild -n cf-space-my-space
kubectl describe cfbuild <build-guid> -n cf-space-my-space

# Check kpack Image and Build objects
kubectl get image -n cf-space-my-space
kubectl get build -n cf-space-my-space

# Get build logs (replaces cf logs during staging)
kubectl logs -n cf-space-my-space \
  -l image.kpack.io/image=<image-name> \
  --all-containers=true \
  --tail=100

# Check if buildpack is available
kubectl get clusterbuilder
kubectl describe clusterbuilder default
```

**Problem: Korifi API server not responding**

```bash
# Check Korifi control plane pods
kubectl get pods -n korifi
kubectl describe pod -n korifi -l app=korifi-api-server

# Check API server logs
kubectl logs -n korifi -l app=korifi-api-server --tail=100

# Check cert-manager certificates (Korifi uses mTLS internally)
kubectl get certificates -n korifi
kubectl get certificaterequests -n korifi

# Check Korifi webhook
kubectl get validatingwebhookconfiguration | grep korifi
kubectl get mutatingwebhookconfiguration | grep korifi
```

**Problem: `cf login` fails against Korifi**

```bash
# Korifi uses an external OIDC provider — check the auth URL config
kubectl get configmap korifi-api-config -n korifi -o yaml | grep -i auth

# Check if Dex (or other IdP) is running
kubectl get pods -n dex 2>/dev/null || kubectl get pods -n auth

# Test the OIDC discovery endpoint
curl -k https://<uaa-or-dex-url>/.well-known/openid-configuration | jq .

# Verify cf CLI target
cf api
cf auth admin --client-credentials  # for admin bootstrap
```

**Common Korifi networking issues summary:**

| Symptom | First check | Command |
|---|---|---|
| App 503 | HTTPProxy status | `kubectl get httpproxy -n <space-ns>` |
| App never starts | Pod image pull | `kubectl get events -n <space-ns>` |
| C2C policy not working | NetworkPolicy labels | `kubectl describe networkpolicy -n <space-ns>` |
| Build fails | kpack Build logs | `kubectl logs -n <space-ns> -l image.kpack.io/build=1` |
| Route DNS not resolving | CFDomain + CoreDNS | `kubectl get cfdomain -A` |
| Login fails | OIDC config | `kubectl get configmap korifi-api-config -n korifi -o yaml` |

> **K8s Engineer's Translation:** Most BOSH CF debugging required `bosh ssh` into a cell, then `monit status` and reading logs from `/var/vcap/sys/log/`. Korifi debugging is entirely `kubectl` — `kubectl describe`, `kubectl logs`, `kubectl get events`. The same tooling you use for any other K8s workload.

---

## Production Checklist

- [ ] Korifi API server deployed with HA (minimum 2 replicas)
- [ ] etcd backed up — all CF state now lives in K8s etcd; treat it like a critical database
- [ ] cert-manager installed and certificate rotation configured
- [ ] External OIDC provider (Dex, Okta, Azure AD) configured for UAA replacement
- [ ] Container registry (Harbor, GCR, ECR) configured with appropriate access controls
- [ ] Image pull secrets provisioned in all CF space namespaces
- [ ] Contour deployed with HA Envoy daemonset
- [ ] TLS wildcard certificate for `*.apps.example.com` provisioned in Contour
- [ ] CNI with NetworkPolicy enforcement installed (Calico or Cilium recommended)
- [ ] Default-deny NetworkPolicy applied to CF space namespaces
- [ ] kpack ClusterBuilder pinned to a specific buildpack version for reproducibility
- [ ] Korifi controllers resource limits set (OOM kills disrupt reconciliation loops)
- [ ] RBAC: CF org manager and space developer roles mapped to K8s RoleBindings reviewed
- [ ] Monitoring: Prometheus scraping Korifi API server, Contour, kpack metrics
- [ ] Alerting: alert on CFBuild failures, Korifi controller error rates, Contour backend 503s
- [ ] Log aggregation: ship Korifi controller logs and app pod logs to central logging
- [ ] Quota enforcement: CFOrgQuota and CFSpaceQuota objects configured
- [ ] Upgrade path documented: Korifi is pre-1.0 as of 2026; pin Helm chart version
- [ ] AI workload networking: if running AI/ML workloads, review Korifi AI Working Group guidance (announced June 2026) for GPU node scheduling support

---

## Quick Reference

### cf CLI commands (identical between BOSH CF and Korifi)

| Action | Command |
|---|---|
| Push an app | `cf push my-app -p ./app` |
| Map a route | `cf map-route my-app apps.example.com --hostname my-app` |
| Unmap a route | `cf unmap-route my-app apps.example.com --hostname my-app` |
| Add C2C policy | `cf add-network-policy frontend --destination-app backend --port 8080 --protocol tcp` |
| Remove C2C policy | `cf remove-network-policy frontend --destination-app backend --port 8080 --protocol tcp` |
| List network policies | `cf network-policies` |
| Scale app | `cf scale my-app -i 3 -m 256M` |
| View app env | `cf env my-app` |
| Set env var | `cf set-env my-app KEY value` |
| Restage app | `cf restage my-app` |
| View logs | `cf logs my-app --recent` |
| SSH into app | `cf ssh my-app` (maps to `kubectl exec`) |

### kubectl commands for Korifi objects

| Action | Command |
|---|---|
| List CF apps | `kubectl get cfapp -n <space-namespace>` |
| List CF routes | `kubectl get cfroute -n <space-namespace>` |
| List CF builds | `kubectl get cfbuild -n <space-namespace>` |
| List CF spaces | `kubectl get cfspace -A` |
| List CF orgs | `kubectl get cforgs -A` |
| List CF domains | `kubectl get cfdomain -A` |
| Watch Contour proxies | `kubectl get httpproxy -n <space-namespace>` |
| Watch NetworkPolicies | `kubectl get networkpolicy -n <space-namespace>` |
| Watch kpack builds | `kubectl get build -n <space-namespace>` |
| Get app pod logs | `kubectl logs -n <space-namespace> -l korifi.cloudfoundry.org/app-guid=<guid>` |
| Get Korifi controller logs | `kubectl logs -n korifi -l app=korifi-controllers --tail=100` |
| Get Korifi API server logs | `kubectl logs -n korifi -l app=korifi-api-server --tail=100` |
| Check Korifi health | `kubectl get pods -n korifi` |

### BOSH CF to Korifi component mapping (quick reference)

| BOSH CF | Korifi | Debug command |
|---|---|---|
| Cloud Controller | Korifi API server | `kubectl logs -n korifi -l app=korifi-api-server` |
| CC Database | etcd (via K8s API) | `kubectl get cfapp -A` |
| Diego BBS | kube-apiserver + scheduler | `kubectl get pods -A` |
| Diego Cell | K8s Node | `kubectl get nodes` |
| Gorouter | Contour (Envoy) | `kubectl get httpproxy -A` |
| NATS | Kubernetes watch/informer | `kubectl get events -A` |
| Route Emitter | Korifi route controller | `kubectl logs -n korifi -l app=korifi-controllers` |
| BOSH DNS | CoreDNS | `kubectl get pods -n kube-system -l k8s-app=kube-dns` |
| UAA | External OIDC (Dex) | `kubectl get pods -n dex` |
| Silk CNI + VPA | K8s CNI + NetworkPolicy | `kubectl get networkpolicy -A` |
| CF blobstore | Container registry | `kubectl get secret image-registry-credentials -A` |

---

## See Also

**Within this course — K8s lessons directly relevant to Korifi:**

- [Lesson 05: Pod Networking and CNI](../lessons/09-cni-specification.md) — How K8s pod networking works; Korifi apps run as standard pods on this network
- [Lesson 06: Kubernetes NetworkPolicy](../lessons/16-network-policies.md) — Korifi C2C policies become NetworkPolicy objects; this lesson explains enforcement
- [Lesson 09: Kubernetes Ingress](../lessons/17-ingress-controllers.md) — Korifi routes become Contour HTTPProxy objects; Ingress concepts apply directly
- [Lesson 10: Envoy and Service Mesh](../lessons/21-service-mesh-istio.md) — Contour uses Envoy; this lesson explains the data plane Korifi routes traffic through
- [Lesson 14: Kubernetes RBAC](../lessons/23-network-security-hardening.md) — CF org/space roles map to K8s RBAC; this lesson is essential for Korifi security
- [Lesson 20: Kubernetes DNS](../lessons/14-coredns-service-discovery.md) — Korifi uses CoreDNS; replaces BOSH DNS for apps.internal

**Within the CF track:**

- [CF-05: Silk CNI and VXLAN Overlay](cf-05-silk-cni-vxlan.md) — The overlay networking Korifi replaces
- [CF-10: Container-to-Container Networking](cf-13-c2c-network-policies.md) — C2C policies that Korifi translates to NetworkPolicy
- [CF-15: BOSH DNS and Service Discovery](cf-03-bosh-dns-service-discovery.md) — The DNS layer Korifi replaces with CoreDNS
- [CF-16: Gorouter Internals](cf-09-gorouter.md) — The routing component Korifi replaces with Contour

---

## Online Resources

- [Korifi GitHub repository](https://github.com/cloudfoundry/korifi) — Source, install guide, and architecture docs; primary reference for 2026 state
- [Korifi installation guide](https://github.com/cloudfoundry/korifi/blob/main/INSTALL.md) — Step-by-step kind/GKE/EKS installation with cert-manager, kpack, and Contour
- [Cloud Foundry V3 API reference](https://v3-apidocs.cloudfoundry.org/) — The API surface Korifi implements; use this to understand what CRDs map to
- [Contour documentation](https://projectcontour.io/docs/) — The ingress controller replacing Gorouter; HTTPProxy CRD reference
- [kpack documentation](https://github.com/buildpacks-community/kpack) — The build system replacing Diego staging; Image, Build, and ClusterBuilder API reference
