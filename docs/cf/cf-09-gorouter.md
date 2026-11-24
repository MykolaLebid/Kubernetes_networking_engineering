# CF-09 — Gorouter: HTTP Routing Architecture

**Track:** CF-C — Ingress and Routing  
**Prerequisite:** CF-02 (Garden Container Networking), CF-04 (Silk CNI) or equivalent  
**Companion K8s lessons:** Lesson 15 — Ingress Controllers, Lesson 16 — Gateway API, Lesson 19 — Service Mesh TLS

---

## Quick Read (10 min)

**What Gorouter is:** CF's built-in HTTP/WebSocket L7 reverse proxy. Every inbound request to any `cf push`-deployed app flows through one or more Gorouter instances sitting behind a load balancer. No Nginx, no Envoy, no Ingress YAML required — Gorouter is the platform's answer to all of those.

**Key mental model:**

- Gorouter holds an **in-memory routing table**: `hostname → [{ cell_ip:port, instance_id }, ...]`
- Routes are registered via **NATS** (pub/sub message bus), not etcd or a K8s API — there is no persistent route store
- **Route Emitter** (on each Diego Cell) publishes `router.register` NATS messages every **20 seconds**; Gorouter sets TTL of **2 minutes** per route entry
- If a Route Emitter stops, routes expire from the table within 2 minutes — traffic drops silently
- Gorouter uses **round-robin** across all healthy app instances for a given route; sticky sessions via `JSESSIONID` cookie are supported
- TLS modes: edge termination (default), passthrough, or full re-encrypt to containers
- WebSocket upgrade is supported — the `Upgrade: websocket` header triggers a connection hijack

**Gorouter in one diagram:**

```mermaid
flowchart LR
    client["External Client\nHTTPS :443"]
    lb["Load Balancer\n(IaaS L4)"]
    gr1["Gorouter 1\n(in-memory route table)"]
    gr2["Gorouter 2\n(in-memory route table)"]
    nats["NATS Message Bus\n(route registration)"]
    re1["Route Emitter\n(Diego Cell 1)"]
    re2["Route Emitter\n(Diego Cell 2)"]
    app1["App Instance 0\nCell1 IP:61001"]
    app2["App Instance 1\nCell2 IP:61002"]

    client -->|"TLS SNI"| lb
    lb -->|"round-robin"| gr1 & gr2
    gr1 & gr2 <-->|"NATS sub router.register"| nats
    re1 & re2 -->|"NATS pub router.register\nevery 20s"| nats
    re1 --- app1
    re2 --- app2
    gr1 -->|"HTTP X-CF-InstanceID"| app1
    gr1 -->|"HTTP X-CF-InstanceID"| app2
```

**CF vs K8s translation (Quick Read):**

| CF Concept | K8s Equivalent |
|-----------|---------------|
| Gorouter | Ingress Controller (nginx/Envoy/Contour) |
| NATS route registration | Ingress resource + controller reconcile loop |
| Route Emitter | Endpoints controller |
| `cf map-route` | `kubectl apply -f ingress.yaml` |
| Sticky session via JSESSIONID | `nginx.ingress.kubernetes.io/affinity: cookie` |
| TCP Router | Service type=NodePort / LoadBalancer (non-HTTP) |

**What you will learn in the Deep Dive:** how Gorouter's routing table is built and maintained, the full NATS registration flow, TLS termination modes, sticky sessions, WebSocket handling, TCP Router for non-HTTP traffic, and how to diagnose route registration failures.

---

## Deep Dive

---

## Practice Setup

You need two terminals for every exercise in this lesson.

**Terminal 1 — cf CLI (your laptop or jumpbox)**

```bash
cf api https://api.cf.example.com --skip-ssl-validation
cf login -u admin
cf target -o myorg -s myspace

# Confirm Gorouter is reachable
curl -sk https://api.cf.example.com/v2/info | jq '.routing_endpoint'
```

**Terminal 2 — BOSH SSH into the Gorouter VM**

```bash
# List deployments
bosh -e my-env deployments

# Find Gorouter VMs
bosh -e my-env -d cf vms | grep router

# SSH into the first Gorouter
bosh -e my-env -d cf ssh router/0

# Once inside — Gorouter runs as a BOSH job
sudo -i
monit status | grep gorouter
ls /var/vcap/jobs/gorouter/
ls /var/vcap/sys/log/gorouter/
```

> **K8s Engineer's Translation:** There is no `kubectl exec` into Gorouter — CF uses BOSH SSH to access platform VMs. `monit` is BOSH's process supervisor, analogous to `systemd` for K8s node daemons like `kubelet` or `kube-proxy`.

---

## 1. Gorouter Architecture and the Routing Table

Gorouter is a single Go binary (`gorouter`) running as a BOSH job on one or more `router` VMs. It maintains a purely in-memory routing table: a map from `(hostname, path-prefix)` to a list of backends, where each backend is a `cell_ip:ephemeral_port` pair plus a unique `instance_id` GUID.

```mermaid
flowchart TB
    subgraph "Gorouter Process"
        rt["Routing Table\n(in-memory map)\nhostname → []Backend"]
        proxy["HTTP Reverse Proxy\n(net/http RoundTripper)"]
        nats_sub["NATS Subscriber\nrouter.register\nrouter.unregister"]
        health["Health Endpoint\n:8080/health"]
        metrics["StatsD / Prometheus\nrouter.requests_total\nrouter.latency"]
    end

    nats["NATS Message Bus"]
    re["Route Emitter\n(per Diego Cell)"]
    client["Inbound HTTP/S"]
    backend["App Container\ncell_ip:ephemeral_port"]

    re -->|"router.register {host, uris, port, tags}"| nats
    nats -->|"push to subscriber"| nats_sub
    nats_sub -->|"upsert with TTL=2min"| rt
    client --> proxy
    proxy -->|"lookup hostname"| rt
    rt -->|"selected backend"| proxy
    proxy -->|"HTTP + X-CF headers"| backend
    proxy --> health
    proxy --> metrics
```

### Routing Table Entry Structure

Each entry in the table corresponds to one app instance registration message received over NATS. The Route Emitter on each Diego Cell publishes the following JSON payload to the `router.register` subject every 20 seconds:

```json
{
  "host": "10.0.1.42",
  "port": 61001,
  "uris": ["myapp.cf.example.com", "myapp-custom.example.com"],
  "app": "6fa7c8a3-beef-4c0d-9abc-123456789abc",
  "instance_id": "0f1e2d3c-4b5a-6978-8796-aabbccddeeff",
  "private_instance_index": "0",
  "server_cert_domain_san": "0f1e2d3c-4b5a-6978-8796-aabbccddeeff",
  "tags": {
    "component": "route-emitter",
    "index": "0"
  }
}
```

Key fields:
- `host` — Diego Cell underlay IP (not the container's Silk IP)
- `port` — ephemeral port opened by the host-side iptables DNAT rule that forwards to container port 8080
- `uris` — one or more hostnames; a single container can serve multiple routes
- `instance_id` — used for sticky session affinity and the `X-CF-InstanceID` header
- `server_cert_domain_san` — SAN in the container's mutual-TLS certificate, used for route integrity verification

> **K8s Engineer's Translation:** The NATS `router.register` message is equivalent to an Endpoints object update in Kubernetes — it tells the proxy where to send traffic for a given hostname. In K8s, the Endpoints controller watches Pod IP changes and writes to the API server. In CF, Route Emitter watches the BBS (Bulletin Board System) for actual LRP state and publishes directly to NATS. No persistent store for routes — everything is rebuilt from live NATS messages.

### Route TTL and Expiry

Gorouter sets a 2-minute TTL on each route entry when it receives a registration. If the Route Emitter stops sending `router.register` heartbeats (cell crash, BBS connectivity loss, process restart), entries expire and traffic to those instances drops with a **502 Bad Gateway**. This is by design — stale routes pointing at dead containers are worse than fast expiry.

```bash
# Terminal 2 — watch Gorouter logs for route registration/expiry
tail -f /var/vcap/sys/log/gorouter/gorouter.stdout.log | grep -E "register|unregister|expire"

# Check the current route table via Gorouter's debug port (requires localhost access)
curl http://localhost:8082/routes | jq 'to_entries | .[0:5]'

# Count total registered routes
curl -s http://localhost:8082/routes | jq 'keys | length'
```

---

## 2. Route Registration Flow

The end-to-end flow from `cf push` to a live route involves four components: CC (Cloud Controller), Diego, Route Emitter, and Gorouter. Understanding this chain is essential for diagnosing "route not found" failures.

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant CC as Cloud Controller
    participant BBS as Diego BBS
    participant RE as Route Emitter (Cell)
    participant NATS as NATS Bus
    participant GR as Gorouter

    Dev->>CC: cf push myapp --route myapp.cf.example.com
    CC->>BBS: DesiredLRP with routes[] annotation
    BBS->>RE: ActualLRP started (instance 0 on Cell 1)
    Note over RE: RE watches BBS state
    RE->>NATS: router.register {host:cell_ip, port:61001, uris:[myapp.cf.example.com]}
    NATS->>GR: deliver registration message
    GR->>GR: upsert routing table entry (TTL=2min)
    Note over RE,GR: RE re-publishes every 20s
    Dev->>GR: GET https://myapp.cf.example.com/
    GR->>GR: lookup myapp.cf.example.com → cell_ip:61001
    GR->>RE: HTTP forward to cell_ip:61001
    Note over RE: iptables DNAT → container:8080
```

### Mapping and Unmapping Routes

```bash
# Terminal 1 — route operations

# List all routes in a space
cf routes

# Map an additional hostname to an existing app
cf map-route myapp cf.example.com --hostname myapp-v2

# Map a path-based route (Gorouter supports prefix matching)
cf map-route myapp cf.example.com --hostname myapp --path /api

# Unmap a route (triggers router.unregister NATS message)
cf unmap-route myapp cf.example.com --hostname myapp-v2

# Delete a route entirely
cf delete-route cf.example.com --hostname myapp-v2 -f

# Check which app owns a route
cf routes | grep myapp
```

### Blue-Green Deployments via Route Mapping

Gorouter's round-robin model makes blue-green deployments a pure route-mapping operation:

```bash
# Push new version as blue (no route yet)
cf push myapp-blue --no-route

# Map production route to blue — Gorouter now splits traffic 50/50
cf map-route myapp-blue cf.example.com --hostname myapp

# Verify both apps get traffic, then unmap green
cf unmap-route myapp cf.example.com --hostname myapp

# Clean up
cf delete myapp -f
cf rename myapp-blue myapp
```

> **K8s Engineer's Translation:** This is equivalent to editing an Ingress `backend` to point to a new Service, or using a Gateway API HTTPRoute with weighted backends. The key difference: CF Gorouter can split traffic between multiple apps on the same route simultaneously (while both have the route mapped), whereas K8s Ingress typically sends all traffic to one Service. For weighted traffic splitting in K8s you need Gateway API `backendRefs` with `weight` fields — CF gets this for free.

---

## 3. TLS, Sticky Sessions, and Advanced Routing

### TLS Termination Modes

Gorouter supports three TLS modes, configured in `gorouter.yml` (the BOSH job property `router.tls_port` and `router.backends.enable_tls`):

| Mode | Client → Gorouter | Gorouter → Container | Use Case |
|------|------------------|---------------------|----------|
| Edge termination | TLS | Plain HTTP | Default; simplest |
| TLS passthrough | TLS (SNI routing only) | TLS (unchanged) | End-to-end encryption, mTLS apps |
| Full re-encrypt | TLS | TLS (new cert) | Compliance, route integrity verification |

**Route Integrity Verification** (full re-encrypt mode): Gorouter presents a certificate to the container whose SAN matches the `instance_id` from the routing table. The container's sidecar TLS agent validates this. If the SAN does not match, Gorouter rejects the backend — this prevents routing to a stale iptables DNAT pointing at the wrong container after a rapid reschedule.

```bash
# Terminal 2 — check TLS config on the running Gorouter
cat /var/vcap/jobs/gorouter/config/gorouter.yml | grep -A5 "tls\|backends"

# Verify which port handles HTTPS termination
ss -tlnp | grep gorouter

# Check container-side TLS cert SAN (from inside a cf ssh session)
# Terminal 1
cf ssh myapp -i 0
# Inside container:
openssl x509 -in /etc/cf-instance-credentials/instance.crt -noout -text | grep -A3 "Subject Alternative Name"
```

### X-Forwarded Headers

Gorouter injects standard proxy headers and CF-specific headers:

```
X-Forwarded-For: <client-ip>
X-Forwarded-Proto: https
X-Request-Start: 1700000000.000
X-CF-InstanceID: 0f1e2d3c-4b5a-6978-8796-aabbccddeeff
X-CF-ApplicationID: 6fa7c8a3-beef-4c0d-9abc-123456789abc
X-CF-InstanceIndex: 0
```

Apps can read `X-CF-InstanceID` to identify which instance is serving a request — useful for debugging uneven load distribution or sticky-session issues.

### Sticky Sessions

Gorouter implements sticky sessions via the `JSESSIONID` cookie (or any cookie named in the `sticky_session_cookie_names` Gorouter configuration). When a response sets a `JSESSIONID` cookie, Gorouter wraps it in a `__VCAP_ID__` cookie containing the encoded `instance_id`. On subsequent requests carrying `__VCAP_ID__`, Gorouter routes to the specific instance rather than round-robining.

```bash
# Terminal 1 — observe sticky session behavior
# First request: no cookie → round-robin assignment
curl -c /tmp/cookies.txt -v https://myapp.cf.example.com/ 2>&1 | grep -E "Set-Cookie|X-CF-InstanceID"

# Second request: __VCAP_ID__ cookie present → pinned to same instance
curl -b /tmp/cookies.txt -v https://myapp.cf.example.com/ 2>&1 | grep "X-CF-InstanceID"

# Verify __VCAP_ID__ decodes to a known instance ID
cf app myapp --guid
```

> **K8s Engineer's Translation:** Sticky sessions in K8s require `nginx.ingress.kubernetes.io/affinity: "cookie"` and `nginx.ingress.kubernetes.io/session-cookie-name: "INGRESSCOOKIE"` annotations. CF Gorouter does this automatically for apps that set `JSESSIONID` — zero config from the app developer, and the cookie is managed by the router, not the app.

### WebSocket Routing

Gorouter detects `Upgrade: websocket` / `Connection: Upgrade` headers and hijacks the connection for bidirectional TCP streaming. No special route configuration is needed — any CF route works for WebSocket as long as the app handles the upgrade.

```bash
# Terminal 1 — test WebSocket upgrade path
curl -v \
  -H "Upgrade: websocket" \
  -H "Connection: Upgrade" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Version: 13" \
  https://myapp.cf.example.com/ws

# Terminal 2 — confirm Gorouter is forwarding the upgrade
tail -f /var/vcap/sys/log/gorouter/gorouter.stdout.log | grep -i websocket
```

### TCP Router (Non-HTTP Traffic)

For TCP apps that do not speak HTTP (databases, MQTT brokers, raw socket servers), CF provides a separate **TCP Router** component. TCP routes use port numbers from the `reservable_ports` range instead of hostnames.

```mermaid
flowchart LR
    client["TCP Client\ntcp.cf.example.com:1024"]
    tclb["L4 Load Balancer"]
    tcpr["TCP Router\n(port-based routing)"]
    cell["Diego Cell\niptables DNAT"]
    cont["App Container\n:8080"]

    client --> tclb
    tclb -->|"round-robin per connection"| tcpr
    tcpr -->|"random Cell IP:ephemeral_port\ntranslates to container:8080"| cell
    cell -->|"iptables DNAT"| cont
```

```bash
# Terminal 1 — create a TCP route
# First, find the TCP router domain
cf router-groups
# Output: default-tcp   tcp

# Create TCP route (CF assigns a random port from reservable_ports)
cf create-route tcp.cf.example.com --random-port

# Map to your app
cf map-route myapp tcp.cf.example.com --port 1025

# List TCP routes
cf routes | grep tcp

# Test
nc -zv tcp.cf.example.com 1025
```

> **K8s Engineer's Translation:** TCP Router is equivalent to `Service type=LoadBalancer` with a specific `nodePort` — it exposes a fixed external port that routes to containers. The key difference is that CF's TCP routing is on-demand and self-service (developers reserve ports), whereas K8s NodePort/LoadBalancer services are typically operator-managed. In K8s, the platform does not give developers a self-service way to open arbitrary L4 ports by default.

---

## 4. Troubleshooting

### Failure Mode 1: 502 Bad Gateway After Deploy

**Symptom:** App returns 502 for 30-120 seconds after `cf push` or after a Diego Cell restart.

**Root cause:** Route Emitter has not yet published `router.register`, or the registration message has not been processed by all Gorouter instances.

**Diagnosis:**

```bash
# Terminal 1 — check app instance state
cf app myapp
# Look for: instances 1/1 (running)

# Check route emitter logs on the cell running your app
# First, find the cell
cf curl /v2/apps/$(cf app myapp --guid)/stats | jq '."0".stats.host'
CELL_IP="10.0.1.42"  # from above

# Terminal 2 — BOSH SSH to the cell
bosh -e my-env -d cf ssh diego_cell/0  # find index from 'bosh vms | grep $CELL_IP'
sudo tail -100 /var/vcap/sys/log/route_emitter/route_emitter.stdout.log | grep -E "register|error|failed"

# Check NATS connectivity from the cell
sudo /var/vcap/packages/nats/bin/nats-sub -s nats://nats:$NATS_PASSWORD@10.0.0.6:4222 "router.register" &
# Wait 20s — should see registration messages
```

### Failure Mode 2: Routes Not Appearing (502 Persistent)

**Symptom:** 502 persists even after the app is confirmed running. No `router.register` messages seen on NATS.

**Diagnosis:**

```bash
# Terminal 2 — on the router VM
# Check Gorouter is healthy
monit status | grep gorouter
curl -s http://localhost:8080/health

# Check NATS connection in Gorouter logs
grep -i "nats\|connect\|disconnect" /var/vcap/sys/log/gorouter/gorouter.stdout.log | tail -20

# Check routing table for the hostname
curl -s http://localhost:8082/routes | jq '.["myapp.cf.example.com"]'
# If null: route not registered. If present: Gorouter has it but something else is wrong.

# Verify Gorouter is listening on expected ports
ss -tlnp | grep gorouter
# Should show: :80, :443 (or 8080/8443), :8082 (debug)
```

### Failure Mode 3: Sticky Sessions Not Working

**Symptom:** Requests with `__VCAP_ID__` cookie are still round-robined to different instances.

**Diagnosis:**

```bash
# Terminal 1 — verify the instance the app was pinned to is still running
cf app myapp
# If instances show < desired, the pinned instance died and Gorouter fell back to round-robin

# Check if __VCAP_ID__ decodes to a live instance
# The cookie value is base64-encoded instance_id
echo "BASE64_VALUE_FROM_COOKIE" | base64 -d

# Compare with running instance GUIDs
cf curl /v2/apps/$(cf app myapp --guid)/stats | jq '.[].stats.instance_guid'
```

### Failure Mode 4: TLS Certificate Errors (Route Integrity)

**Symptom:** Gorouter returns 526 (SSL Handshake Failed) or logs `tls: bad certificate`.

**Diagnosis:**

```bash
# Terminal 2 — on router VM
grep -i "tls\|certificate\|handshake" /var/vcap/sys/log/gorouter/gorouter.stdout.log | tail -30

# Check if the container cert SAN matches the instance_id in the routing table
# Terminal 1 — get instance ID from routing table
curl -s http://localhost:8082/routes | jq '.["myapp.cf.example.com"][0].instance_id'

# cf ssh into the app and inspect cert
cf ssh myapp -i 0
openssl x509 -in /etc/cf-instance-credentials/instance.crt -noout -text | grep -A5 "Subject Alternative"
# SAN should contain the instance_id GUID
```

### Failure Mode 5: High Latency / Uneven Instance Load

**Symptom:** Some app instances are overloaded; Gorouter's round-robin is not distributing evenly.

**Diagnosis:**

```bash
# Terminal 2 — Gorouter metrics (if StatsD/Prometheus is configured)
curl -s http://localhost:8080/metrics | grep -E "router_requests|router_latency|router_responses"

# Check per-instance request counts via app metrics
# Terminal 1
cf ssh myapp -i 0 -- ps aux | grep "ruby\|java\|node\|python"

# Check if sticky sessions are causing the skew
curl -b /tmp/cookies.txt -v https://myapp.cf.example.com/ 2>&1 | grep "X-CF-InstanceIndex"
# If always 0: sticky session is pinning all sessions to instance 0

# Verify Gorouter sees all instances
curl -s http://localhost:8082/routes | jq '.["myapp.cf.example.com"] | length'
# Should equal: cf app myapp | grep instances
```

> **K8s Engineer's Translation:** Uneven load in K8s is a common problem with iptables-mode kube-proxy (random, not least-connections) and with Ingress NGINX (also round-robin by default). CF Gorouter has the same limitation. The fix in both ecosystems is an application-level load balancing strategy (consistent hashing, least-connections) which requires a service mesh (Istio/Linkerd in K8s, or CF's forthcoming Envoy sidecar integration).

### Quick Diagnostic Checklist

```bash
# 1. Is the app running?
cf app myapp | grep -E "instances|state"

# 2. Are routes mapped?
cf routes | grep myapp

# 3. Is Gorouter healthy?
# (From router VM via BOSH SSH)
curl -s http://localhost:8080/health && echo "OK"

# 4. Is the route in the routing table?
curl -s http://localhost:8082/routes | jq 'keys | map(select(test("myapp")))'

# 5. Are NATS registration messages flowing?
# (From any CF VM with NATS access)
/var/vcap/packages/nats/bin/nats-sub -s nats://... "router.register" | head -5

# 6. Is the Diego Cell healthy?
bosh -e my-env -d cf vms --vitals | grep diego_cell

# 7. Is Route Emitter running on the cell?
# (From target cell via BOSH SSH)
monit status | grep route_emitter
```

---

## Production Checklist

- [ ] Deploy at least 2 Gorouter instances behind an IaaS L4 load balancer — single Gorouter is a hard SPOF for all HTTP traffic
- [ ] Set Gorouter `max_backends_per_app` to match your expected max instance count per app
- [ ] Enable route integrity verification (full re-encrypt TLS to containers) for PCI/HIPAA workloads
- [ ] Configure `sticky_session_cookie_names` to include all session cookie names used by apps (not just JSESSIONID)
- [ ] Set `router.drain_timeout` to match your app's graceful shutdown time — prevents in-flight requests being dropped during rolling deploys
- [ ] Monitor `router.total_routes` gauge — sudden drops indicate Route Emitter/NATS connectivity issues
- [ ] Monitor `router.responses.5xx` rate — spikes indicate backend failures or misrouted requests
- [ ] Monitor `router.latency` p99 — spikes often indicate Diego Cell resource pressure, not Gorouter itself
- [ ] Size `reservable_ports` range on TCP Router before go-live — expanding the range requires Gorouter restart
- [ ] Confirm TLS cipher suites in `gorouter.yml` meet your compliance baseline; default set includes TLS 1.2+
- [ ] Set `router.forwarded_client_cert` to `sanitize_set` in production to prevent header injection by clients claiming to be internal services
- [ ] Test WebSocket routes explicitly after Gorouter upgrades — connection hijack behavior has changed between versions
- [ ] Validate blue-green route mapping automation in staging before using in production — partial route-mapping windows can cause mixed-version traffic

---

## Quick Reference

| Task | Command |
|------|---------|
| List routes in a space | `cf routes` |
| Map route to app | `cf map-route APP DOMAIN --hostname HOST` |
| Map path-based route | `cf map-route APP DOMAIN --hostname HOST --path /api` |
| Unmap route | `cf unmap-route APP DOMAIN --hostname HOST` |
| Delete a route | `cf delete-route DOMAIN --hostname HOST -f` |
| Create TCP route (random port) | `cf create-route tcp.DOMAIN --random-port` |
| List router groups | `cf router-groups` |
| Check app instance health | `cf app APP` |
| Get app GUID | `cf app APP --guid` |
| Get app instance stats | `cf curl /v2/apps/GUID/stats` |
| SSH into app instance | `cf ssh APP -i INDEX` |
| Check Gorouter health | `curl http://localhost:8080/health` (from router VM) |
| Dump full routing table | `curl http://localhost:8082/routes` (from router VM) |
| Count registered routes | `curl -s http://localhost:8082/routes \| jq 'keys \| length'` |
| Watch Gorouter access log | `tail -f /var/vcap/sys/log/gorouter/access.log` |
| Watch Gorouter error log | `tail -f /var/vcap/sys/log/gorouter/gorouter.stdout.log` |
| Check Route Emitter | `monit status \| grep route_emitter` (from Diego Cell) |
| NATS sub to route events | `/var/vcap/packages/nats/bin/nats-sub -s nats://HOST "router.register"` |
| Check BOSH job config | `cat /var/vcap/jobs/gorouter/config/gorouter.yml` |

---

## See Also

**K8s lessons in this course:**

- **Lesson 15 — Ingress Controllers:** Nginx and HAProxy ingress controllers implement the same L7 routing model as Gorouter, but require explicit Ingress resource YAML and a controller deployment. Compare Gorouter's NATS-driven auto-registration with the Ingress controller's watch loop over Ingress resources.
- **Lesson 16 — Gateway API:** The successor to Ingress in K8s. HTTPRoute resources provide path-matching, header manipulation, and weighted traffic splitting — features that CF Gorouter provides automatically via route mapping. Korifi (CF on K8s, 2026) replaces Gorouter with Contour, which implements Gateway API.
- **Lesson 19 — Service Mesh TLS:** Covers mTLS between services, certificate rotation, and SPIFFE/SPIRE identity — the K8s equivalents of CF route integrity verification and the CredHub-issued container certificates used in full re-encrypt mode.
- **Lesson 11 — iptables and kube-proxy:** The DNAT rules that CF's TCP Router and host-port forwarding use on Diego Cells are identical in mechanism to kube-proxy iptables rules for NodePort services. Reading this lesson will make the CF iptables chain easier to understand.

---

## Online Resources

- [Gorouter architecture (CF docs)](https://docs.cloudfoundry.org/concepts/cf-routing-architecture.html) — official overview of routing components, NATS message bus, and route registration flow
- [CF Routing Release on GitHub](https://github.com/cloudfoundry/routing-release) — source for Gorouter, TCP Router, and Route Registrar BOSH jobs; `config/gorouter.yml.erb` shows all tunable properties
- [Route Services in CF](https://docs.cloudfoundry.org/services/route-services.html) — covers binding service brokers into the routing path (rate limiting, auth, logging) — CF's answer to K8s admission webhooks on ingress traffic
- [CF Routing Acceptance Tests](https://github.com/cloudfoundry/routing-acceptance-tests) — the upstream integration test suite; reading the test cases is the most reliable way to understand edge-case routing behavior
- [Korifi Routing (Contour)](https://github.com/cloudfoundry/korifi) — 2026 CF-on-K8s project; CFRoute CRD is translated to Contour HTTPProxy resources, replacing Gorouter with a Gateway API-compatible Envoy proxy
