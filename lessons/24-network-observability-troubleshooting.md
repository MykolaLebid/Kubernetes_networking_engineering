# Lesson 24 — Network Observability and Troubleshooting

> **Track:** Network Foundation — Bare Metal & Cloud | **Prerequisites:** All previous lessons — this is the capstone | **Duration:** ~3 hours

> **Goal:** Diagnose any Kubernetes network failure — from pod unreachability to DNS timeouts — using a structured L1-to-L7 methodology and tools including Hubble, netshoot, tcpdump, and Prometheus metrics.


**Jump to:** [Theory](#theory) · [Practice](#practice) · [Troubleshooting](#troubleshooting) · [Production Checklist](#production-checklist) · [Quick Reference](#quick-reference) · [Check Your Understanding](#check-your-understanding)

---

## Theory

## 1. Systematic Troubleshooting Methodology

Work from the bottom of the stack up:

```mermaid
flowchart TD
    L1["L1/L2: Physical / Link — NIC up? veth wired? Interface up?"]
    L3["L3: IP — Route correct? ip_forward on? MTU ok?"]
    L4["L4: TCP/UDP — conntrack full? iptables blocking?"]
    L7["L7: Application — DNS resolving? TLS cert valid? HTTP 200?"]
    K8S["Kubernetes — Service exists? Endpoint healthy? NetworkPolicy denying?"]
    CNI["CNI — Pod IP assigned? veth wired? IPAM exhausted?"]

    L1 --> L3 --> L4 --> L7 --> K8S --> CNI

    style L1 fill:#e8f4fd,stroke:#2196F3
    style L3 fill:#e8f5e9,stroke:#4CAF50
    style L4 fill:#fff3e0,stroke:#FF9800
    style L7 fill:#f3e5f5,stroke:#9C27B0
    style K8S fill:#fce4ec,stroke:#E91E63
    style CNI fill:#e0f2f1,stroke:#009688
```

**The golden rule:** confirm each layer before moving up. Don't start at Kubernetes if you haven't confirmed the node NIC is up.

```mermaid
sequenceDiagram
    participant Eng as Engineer
    participant Node as Linux Node (minikube ssh)
    participant CNI as cilium / calicoctl
    participant K8S as kubectl / kube-apiserver
    participant App as netshoot / curl

    Eng->>Node: ip link / ss -tlnp / ping gateway
    Node-->>Eng: L2/L3 OK or FAIL
    Eng->>CNI: cilium status / calicoctl node status
    CNI-->>Eng: CNI healthy or FAIL (BGP/VXLAN down)
    Eng->>K8S: kubectl get ep / netpol / svc
    K8S-->>Eng: Service+Endpoint present or missing
    Eng->>App: nslookup / curl -v http://svc:port
    App-->>Eng: DNS resolved / HTTP status code
    Note over Eng,App: Stop at first layer that fails — fix before proceeding up
```

---

## 2. The Diagnostic Pod

Keep a debug pod manifest ready:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: netshoot
  namespace: default
spec:
  containers:
    - name: netshoot
      image: nicolaka/netshoot
      command: ["sleep", "infinity"]
  nodeSelector:
    kubernetes.io/hostname: "node-to-debug"  # pin to specific node
```

```bash
# Or one-liner:
kubectl run -it --rm netshoot --image=nicolaka/netshoot -- bash
# expect: bash prompt with curl, nslookup, tcpdump, ss, traceroute, iperf3

# In the same network namespace as a running pod:
kubectl debug -it <pod-name> --image=nicolaka/netshoot --target=<container-name>
# expect: shares network namespace of target — same IP, same routes

# nsenter trick (from node — sees pod network namespace):
NODE_PID=$(kubectl get pod <pod> -o jsonpath='{.status.podIP}')
# SSH to node, find PID:
crictl inspect $(crictl ps | grep <pod-name> | awk '{print $1}') | jq '.info.pid'
nsenter -n -t <PID> -- ss -tlnp
# expect: socket table from inside the pod
```

---

## 3. Pod Connectivity Checklist

```bash
# SYMPTOM: Pod A cannot reach Pod B

# Step 1: Can Pod A reach its own gateway?
kubectl exec -it pod-a -- ping -c3 $(ip route | grep default | awk '{print $3}')
# expect: 0% packet loss

# Step 2: Can Pod A reach Pod B's IP directly?
POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
kubectl exec -it pod-a -- ping -c3 $POD_B_IP
# If fail → routing or NetworkPolicy issue

# Step 3: Is there a NetworkPolicy blocking traffic?
# Check policies selecting pod-a (egress) and pod-b (ingress)
kubectl get networkpolicy -n default -o yaml | grep -A10 "podSelector"
# Use Cilium policy trace:
cilium policy trace --src-pod default/pod-a --dst-pod default/pod-b --dport 80
# expect: "Final verdict: allowed" or "Final verdict: denied — reason: ..."

# Step 4: Is the route present?
NODE=$(kubectl get pod pod-b -o jsonpath='{.spec.nodeName}')
# SSH to node
ssh $NODE
ip route get $POD_B_IP
# expect: a valid route showing the veth or tunnel interface

# Step 5: Cross-node — is VXLAN/BGP working?
# Check CNI status
calicoctl node status   # or: cilium status
# expect: BGP peer state Established, VXLAN/WireGuard active

# Step 6: Packet capture
# On pod-b's node:
tcpdump -i any -n host $POD_B_IP
# expect: ICMP packets arriving from Pod A's IP
```

---

## 4. Service Connectivity Checklist

```bash
# SYMPTOM: Pod cannot reach Service

# Step 1: Does the service exist?
kubectl get svc web -n default
# expect: ClusterIP shows an IP address (not <none>)

# Step 2: Does it have endpoints?
kubectl get endpoints web -n default
# expect: IP:port entries — if empty: selector doesn't match pods or pods not Ready
kubectl describe endpoints web -n default
# shows notReadyAddresses if pods are failing health checks

# Step 3: Is the DNS name resolving?
kubectl exec -it pod-a -- nslookup web.default.svc.cluster.local
# expect: returns ClusterIP address
kubectl exec -it pod-a -- nslookup web   # short name
# expect: same result via search domain

# Step 4: Is the ClusterIP reachable?
CLUSTER_IP=$(kubectl get svc web -o jsonpath='{.spec.clusterIP}')
kubectl exec -it pod-a -- curl -v http://$CLUSTER_IP:80
# expect: HTTP response — if fails: iptables DNAT rule missing

# Step 5: Are iptables DNAT rules present?
iptables -t nat -L KUBE-SERVICES -n | grep $CLUSTER_IP
# expect: rule with "/* web/default:http cluster IP */"

# Step 6: Is kube-proxy running and healthy?
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-proxy | tail -20
# expect: "Syncing iptables rules" messages without ERROR
```

---

## 5. DNS Troubleshooting

```bash
# SYMPTOM: DNS lookups failing or slow

# Step 1: Can pod reach CoreDNS?
kubectl exec -it pod-a -- nc -vzu 10.96.0.10 53
# expect: "open" (UDP) — if fails: NetworkPolicy blocking CoreDNS

# Step 2: Does a simple lookup work?
kubectl exec -it pod-a -- nslookup kubernetes.default.svc.cluster.local
# expect: returns 10.96.0.1 (or configured API server ClusterIP)

# Step 3: Enable CoreDNS query logging
kubectl edit cm -n kube-system coredns
# Add: log  (inside the .:53 { block)
kubectl rollout restart deployment -n kube-system coredns

# Watch queries
kubectl logs -n kube-system -l k8s-app=kube-dns -f | grep -v "NOERROR"
# expect: each query logged — look for NXDOMAIN or SERVFAIL

# Step 4: Check ndots behavior
kubectl exec -it pod-a -- cat /etc/resolv.conf
# expect: "ndots:5" — means short names trigger 5 search domain tries before bare lookup
# high ndots:5 → many fallback queries for external names

# Step 5: Check CoreDNS metrics
kubectl port-forward -n kube-system svc/kube-dns 9153:9153 &
curl -s http://localhost:9153/metrics | grep coredns_dns_request_duration
# expect: histogram buckets with 95th percentile < 5ms for healthy DNS

# Step 6: Check for conntrack UDP race condition
# (symptom: 5-second DNS timeouts)
dmesg | grep "nf_conntrack: table full"
# if present: conntrack exhaustion is causing DNS drops
sysctl net.netfilter.nf_conntrack_count
sysctl net.netfilter.nf_conntrack_max
# expect: count < 80% of max
```

---

## 6. Latency Investigation

```bash
# SYMPTOM: High latency between pods

# Step 1: Baseline measurement
kubectl exec -it pod-a -- \
  for i in $(seq 10); do curl -w "%{time_total}\n" -o /dev/null -s http://web; done
# expect: p99 < 5ms for in-cluster pod-to-pod on modern hardware

# Step 2: Check for packet loss
kubectl exec -it pod-a -- ping -c100 -f $POD_B_IP
# "%" column shows packet loss
# expect: 0% loss for healthy cluster

# Step 3: MTU mismatch (causes fragmentation → latency)
kubectl exec -it pod-a -- ping -M do -s 1422 $POD_B_IP  # VXLAN
# If "Message too long" → MTU mismatch
# Check effective MTU
kubectl exec -it pod-a -- ip link show eth0 | grep mtu
# expect: 1450 (VXLAN) or 1360 (WireGuard over VXLAN) or 1500 (native)

# Step 4: CPU throttling on pods (affects packet processing)
kubectl top pod pod-a
kubectl describe pod pod-a | grep -A5 "Limits\|Requests"
# expect: CPU usage well below limits — high throttling causes tail latency

# Step 5: conntrack contention
# High conntrack lookup latency on busy nodes:
cat /proc/net/stat/nf_conntrack
# expect: low "searched" vs "found" ratio

# Step 6: Node CPU for network interrupts
# On node:
watch -n1 'cat /proc/interrupts | grep -E "eth0|mlx5"'
# expect: interrupts spread evenly across CPUs (RSS/multi-queue working)
```

---

## 7. Packet Capture Techniques

```bash
# Capture on a specific pod's veth (from the host)
# First, find the veth
POD_ID=$(kubectl get pod pod-a -o jsonpath='{.metadata.uid}')
# Find matching veth on node:
ip link show | grep -i cali
# Then capture:
tcpdump -i cali1234abcd -n -w /tmp/pod-a.pcap
# expect: raw packets — open in Wireshark to decode

# Capture inside pod
kubectl exec -it pod-a -- tcpdump -i eth0 -n -w /tmp/capture.pcap
# Copy out:
kubectl cp pod-a:/tmp/capture.pcap ./pod-a.pcap
# expect: pcap file on local disk

# ksniff — kubectl plugin for pod packet capture
kubectl sniff pod-a -n default -o ./pod-a.pcap
# expect: live capture piped to Wireshark (requires krew install sniff)

# Capture VXLAN encapsulated traffic (between nodes)
tcpdump -i eth0 -n udp port 4789 -w /tmp/vxlan.pcap
# expect: UDP frames with inner IP headers visible in Wireshark

# View in Wireshark
# wireshark ./pod-a.pcap
# or analyze with tshark:
tshark -r pod-a.pcap -T fields -e frame.number -e ip.src -e ip.dst -e tcp.dstport
# expect: columns showing inner IP flow src/dst/port
```

---

## 8. Hubble — Flow-Level Observability

```bash
# Install Hubble CLI
curl -L --fail --remote-name-all \
  https://github.com/cilium/hubble/releases/download/v0.13.0/hubble-linux-amd64.tar.gz
tar xzvf hubble-linux-amd64.tar.gz
mv hubble /usr/local/bin/

# Forward Hubble relay
cilium hubble port-forward &

# Watch all flows
hubble observe
# expect: stream of src → dst flows with verdict (FORWARDED/DROPPED)

# Watch denied flows (policy violations)
hubble observe --verdict DROPPED --all-namespaces
# expect: flows that NetworkPolicy or Istio AuthorizationPolicy blocked

# Flow for specific pod
hubble observe --from-pod default/frontend --to-pod default/backend
# expect: flows between those two pods with HTTP method and status

# Count flows per destination
hubble observe --all-namespaces -o json | \
  jq -r '.flow | .destination.namespace + "/" + .destination.pod_name' | \
  sort | uniq -c | sort -rn | head -20
# expect: top-N pods by received flow count

# HTTP flows
hubble observe --protocol http --all-namespaces | head -20
# expect: HTTP method, path, response code for each flow

# Service connectivity map (Hubble UI)
cilium hubble ui
# expect: browser opens at localhost:12000 with service topology graph
```

### Hubble Key Metrics

| Metric | PromQL | What it shows |
|--------|--------|---------------|
| Total drop rate | `rate(cilium_drop_count_total[5m])` | Policy drops per second |
| Drop by reason | `sum by (reason) (rate(cilium_drop_count_total[5m]))` | Why traffic is dropped |
| iptables rule count | `felix_iptables_rules_total` | Calico iptables rule count |
| conntrack entries | `node_nf_conntrack_entries` | Current conntrack table usage |
| DNS error rate | `rate(coredns_dns_responses_total{rcode!="NOERROR"}[5m])` | CoreDNS failures |

---

## 9. Key Metrics to Monitor

```bash
# Kubernetes network metrics (from kube-state-metrics + node-exporter)
# In Prometheus/Grafana:

# Node network throughput
rate(node_network_receive_bytes_total{device="eth0"}[5m])
rate(node_network_transmit_bytes_total{device="eth0"}[5m])
# expect: matches expected app traffic patterns

# Network errors
rate(node_network_receive_errs_total[5m])
rate(node_network_transmit_errs_total[5m])
# expect: near-zero; spikes indicate hardware/driver issues

# conntrack usage
node_nf_conntrack_entries / node_nf_conntrack_entries_limit
# expect: < 0.8 (80%) — above this DNS and new connections start dropping

# DNS query rate
rate(coredns_dns_requests_total[5m])
# baseline this per-pod for capacity planning

# DNS error rate
rate(coredns_dns_responses_total{rcode!="NOERROR"}[5m])
# expect: near-zero; NXDOMAIN spike = broken service names

# kube-proxy sync latency
rate(kubeproxy_sync_proxy_rules_duration_seconds_bucket[5m])
# expect: < 100ms p99; spikes correlate with iptables rule churn
```

### Industry Applications

| Company / Project | Context | Technology from this lesson | Outcome |
|---|---|---|---|
| Datadog | eBPF-based network monitoring for 10,000+ customer K8s clusters | Hubble / eBPF flow telemetry + Prometheus metrics | Real-time per-pod network visibility without sidecar overhead |
| AWS (EKS) | Network forensics and incident response | VPC Flow Logs + CloudWatch + netshoot | Post-incident packet-level analysis for security investigations |
| Google (GKE) | Real-time service topology for GKE customers | Hubble (Cilium) flow exporter + service map UI | Automated dependency mapping across thousands of services |
| LinkedIn | Distributed tracing across 1,000+ microservices | eBPF probes + custom conntrack metrics | Sub-millisecond latency anomaly detection without application instrumentation |
| Banking (PCI-DSS cluster) | conntrack table saturation during Black Friday caused intermittent payment gateway TCP resets | Hubble flows (drop verdict) + `conntrack -S` on node | Identified table at 98% capacity at peak; increased `nf_conntrack_max` and added conntrack usage alert to prevent recurrence |

---

## Practice

### Environment Setup

```bash
# Terminal 1 — minikube Linux node
minikube ssh
ss -s           # socket summary — total established/closed counts
ss -tlnp        # listening TCP sockets with process names
conntrack -L 2>/dev/null | head -10  # conntrack table — expect: NAT entries

# Terminal 2 — Mac (kubectl + hubble)
hubble observe --last 20 2>/dev/null || echo "hubble not running — try: cilium hubble enable"
kubectl run netshoot --image=nicolaka/netshoot --rm -it --restart=Never -- bash
# expect: bash prompt inside netshoot — all network debug tools available
```

### Hands-On Lab

```bash
# SYMPTOM: Pod A cannot reach Pod B — systematic diagnosis

# Step 1: Can Pod A reach its own gateway?
kubectl exec -it pod-a -- ping -c3 $(ip route | grep default | awk '{print $3}')
# expect: 0% packet loss

# Step 2: Can Pod A reach Pod B's IP directly?
POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
kubectl exec -it pod-a -- ping -c3 $POD_B_IP

# Step 3: Trace Cilium policy decision
cilium policy trace --src-pod default/pod-a --dst-pod default/pod-b --dport 80
# expect: "Final verdict: allowed" or specific deny reason

# Step 4: Check DNS resolution
kubectl exec -it pod-a -- nslookup kubernetes.default.svc.cluster.local
# expect: returns ClusterIP

# Step 5: Check conntrack table usage (5-second DNS timeout root cause)
dmesg | grep "nf_conntrack: table full"
cat /proc/sys/net/netfilter/nf_conntrack_count
# expect: count < 80% of nf_conntrack_max

# Step 6: MTU fragmentation check
kubectl exec -it pod-a -- ping -M do -s 1422 $POD_B_IP
# If "Message too long" → MTU mismatch; set CNI MTU to 1450 for VXLAN

# Step 7: Packet capture on veth
# From the node — find pod veth
ip link show | grep -i cali
tcpdump -i cali1234abcd -n -w /tmp/pod-a.pcap
kubectl cp pod-a:/tmp/capture.pcap ./pod-a.pcap
```

### Configuration Reference

See Hubble metrics reference in Theory Section 8 above.

---

## Troubleshooting

| Symptom | Likely Cause | Diagnostic Command | Fix |
|---------|-------------|-------------------|-----|
| Pod can't ping pod | NetworkPolicy block or missing route | `cilium policy trace --src-pod ns/a --dst-pod ns/b --dport 80` | Add NetworkPolicy allow rule or fix CNI route |
| Pod can't reach service | No endpoints or kube-proxy not synced | `kubectl get endpoints <svc>; iptables -t nat -L KUBE-SERVICES -n \| grep <clusterIP>` | Fix pod readiness probe or restart kube-proxy |
| DNS timeout (5s) | conntrack UDP race or CoreDNS crash | `dmesg \| grep conntrack; kubectl logs -n kube-system -l k8s-app=kube-dns` | Increase conntrack table size or scale CoreDNS replicas |
| Intermittent connections | conntrack table exhausted | `cat /proc/sys/net/netfilter/nf_conntrack_count` vs max | `sysctl -w net.netfilter.nf_conntrack_max=524288` |
| High latency | MTU fragmentation (VXLAN overhead ignored) | `ping -M do -s 1422 <pod-ip>` | Lower pod MTU to 1450 for VXLAN or 1360 for WireGuard |
| LoadBalancer pending | CCM not installed or cloud IAM insufficient | `kubectl describe svc <svc> \| grep Events` | Install cloud CCM or grant IAM role for LB provisioning |
| BGP not established | TCP/179 blocked or ASN mismatch | `calicoctl node status \| grep BGP; telnet <peer> 179` | Open TCP 179 and verify peer ASN config |
| VXLAN drops | UDP/4789 blocked on firewall or MTU exceeded | `tcpdump -i eth0 -n udp port 4789` | Open UDP 4789 and set CNI MTU to 1450 |

---

## Production Checklist

- [ ] Hubble or equivalent flow exporter deployed and exporting to centralized log store
- [ ] Prometheus alerts configured for `cilium_drop_count_total` and `node_nf_conntrack_entries`
- [ ] netshoot (or equivalent debug image) added to cluster image pull policy allowlist
- [ ] `ss -tlnp` and `conntrack -L` available on nodes — `conntrack-tools` package installed
- [ ] MTU set correctly for CNI overlay (1450 VXLAN, 1360 WireGuard+VXLAN) — not default 1500
- [ ] CoreDNS scaled to minimum 2 replicas with PodAntiAffinity across nodes
- [ ] Network troubleshooting runbook stored in team wiki with this lesson's methodology

---

## Common Anti-Patterns

| What people do | Why it breaks | Correct approach |
|----------------|--------------|-----------------|
| Start troubleshooting at Kubernetes layer (services, policies) | Lower layers (MTU, routing, CNI) may be broken — Kubernetes can't fix a missing route | Always start at L1/L2 and work up: NIC → route → conntrack → K8s |
| Use `kubectl exec curl` as the only test | Passes through kube-proxy DNAT — hides raw routing issues | Also test pod-IP directly and use tcpdump on the node |
| Run `tcpdump` without specifying interface | Captures loopback and all interfaces — overwhelming noise | Always specify `-i cali1234` (veth) or `-i eth0 udp port 4789` |
| Ignore MTU for overlay networks | 1500-byte packets are fragmented in VXLAN tunnels — silent performance loss | Calculate: physical MTU (1500) − VXLAN header (50) = 1450 max pod MTU |
| Assume DNS failure = CoreDNS issue | conntrack table exhaustion or NetworkPolicy blocking DNS are more common | Check `dmesg \| grep conntrack` and `netpol` before touching CoreDNS config |

---

## Quick Reference

| Use Case | Command |
|----------|---------|
| Watch denied flows real-time | `hubble observe --verdict DROPPED --all-namespaces` |
| Trace Cilium policy decision | `cilium policy trace --src-pod ns/pod-a --dst-pod ns/pod-b --dport 80` |
| Check service endpoints | `kubectl get endpoints <svc> -n <ns>` |
| Verify ClusterIP DNAT rule | `iptables -t nat -L KUBE-SERVICES -n \| grep <clusterIP>` |
| Capture pod traffic from node | `tcpdump -i cali<veth> -n -w /tmp/out.pcap` |
| Check conntrack table usage | `cat /proc/sys/net/netfilter/nf_conntrack_count` |
| Test DNS resolution from pod | `kubectl exec -it pod -- nslookup <svc>.default.svc.cluster.local` |
| Inspect socket table inside pod | `kubectl exec -it pod -- ss -tlnp` |
| Run netshoot debug pod | `kubectl run -it --rm netshoot --image=nicolaka/netshoot -- bash` |
| Debug in target pod network ns | `kubectl debug -it <pod> --image=nicolaka/netshoot --target=<container>` |
| Check MTU fragmentation | `kubectl exec -it pod -- ping -M do -s 1422 <dest-ip>` |
| View Hubble service topology | `cilium hubble ui` |

---

## Summary and Graduation

You have covered the full Kubernetes networking stack:

```
Lessons 01-04: Linux primitives — namespaces, veth, routing, iptables
Lessons 05-06: Overlay networks and BGP
Lessons 07-08: Bare metal infrastructure and cloud provider networking
Lesson  09:    CNI specification
Lessons 10-11: Calico and Cilium — the two dominant CNIs
Lessons 12-13: Services and DNS — the discovery layer
Lesson  14:    Network Policies — microsegmentation
Lessons 15-16: Ingress and Gateway API — L7 traffic
Lessons 17-18: Load balancers — bare metal and cloud
Lesson  19:    Istio service mesh
Lesson  20:    eBPF/XDP — the kernel layer
Lesson  21:    IPv6 and dual-stack
Lesson  22:    Multi-cluster networking
Lesson  23:    Security hardening
Lesson  24:    Observability and troubleshooting ← you are here
```

You can now trace a packet from a pod's application socket all the way to its destination across any infrastructure — and diagnose where it breaks.

> **See also:** [Lesson 23 — Network Security Hardening](23-network-security-hardening.md) for Hubble verdict filtering to build security policies. [Lesson 21 — Istio](21-service-mesh-istio.md) for `istioctl proxy-config` and Envoy access log troubleshooting.


---

## 10. OpenTelemetry Integration

OpenTelemetry (OTel) is the CNCF standard for collecting traces, metrics, and logs from any infrastructure layer. For Kubernetes network engineers it has two specific entry points: **OBI** (the eBPF-based zero-code auto-instrumentation agent) and the **Hubble OTLP exporter** (which turns Cilium flow records into distributed traces). Both feed the same OTel Collector pipeline and produce data you can query alongside your existing Prometheus and Hubble dashboards.

> **K8s Engineer's Translation:** OTel does not replace Hubble or Prometheus — it unifies their output. L4 flow records from Cilium become trace spans. Node-exporter metrics become OTLP metrics. Pod logs become structured log records. All three land in the same backend so a single Grafana query can correlate a TCP drop (Hubble span) with a CPU spike (Prometheus metric) with an error log (Loki record).

### 10.1 Architecture

```mermaid
flowchart LR
    OBI["OBI DaemonSet\n(eBPF zero-code)"]
    HUB["Cilium Hubble\n(L4 flow records)"]
    SDK["App SDK\n(traces / logs)"]
    COL["OTel Collector\n(fan-out hub)"]
    PROM["Prometheus\n(metrics)"]
    TEMPO["Grafana Tempo\n(traces)"]
    LOKI["Loki\n(logs)"]

    OBI -- OTLP/gRPC --> COL
    HUB -- OTLP/gRPC --> COL
    SDK -- OTLP/gRPC --> COL
    COL -- remote_write --> PROM
    COL -- OTLP --> TEMPO
    COL -- loki_push --> LOKI

    style COL fill:#e8f4fd,stroke:#2196F3
    style OBI fill:#e8f5e9,stroke:#4CAF50
    style HUB fill:#e8f5e9,stroke:#4CAF50
```

**Three signals:**

| Signal | Stability (2026) | Used for |
|--------|-----------------|----------|
| Traces | Stable — all major languages | Request paths, latency root-cause |
| Metrics | Stable — Go, Java, Python, .NET | Throughput, error rates, saturation |
| Logs | Stable in .NET/PHP; RC in Go | Structured events, Tetragon audit |
| Profiles | **Alpha** | CPU/memory flamegraphs — not production-ready |

**Minimal Collector config** (receiver → batch → dual export):

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024

exporters:
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
  otlp/tempo:
    endpoint: http://tempo:4317
    tls:
      insecure: true
  loki:
    endpoint: http://loki:3100/loki/api/v1/push

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [loki]
```

Deploy as a Deployment:

```bash
kubectl create configmap otel-collector-config \
  --from-file=config.yaml=otel-collector-config.yaml \
  -n monitoring

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
        - name: collector
          image: otel/opentelemetry-collector-contrib:latest
          args: ["--config=/conf/config.yaml"]
          ports:
            - containerPort: 4317   # OTLP gRPC
            - containerPort: 4318   # OTLP HTTP
          volumeMounts:
            - name: config
              mountPath: /conf
      volumes:
        - name: config
          configMap:
            name: otel-collector-config
EOF
```

---

### 10.2 OBI v1.0 — eBPF Zero-Code Instrumentation

**OBI** (OpenTelemetry eBPF Instrumentation) was originally Grafana's Beyla project. Grafana donated it to the CNCF/OTel project in 2025; it was renamed to OBI and reached v1.0 GA in 2026.

**What it does:** hooks into the Linux kernel via eBPF (kernel 5.8+) to intercept HTTP, gRPC, SQL, and other protocol calls at the system-call boundary. No sidecar. No code change. No pod restart. Runs as a cluster-wide DaemonSet.

**Supported protocols:** HTTP/HTTPS, HTTP/2, gRPC, SQL (MySQL/PostgreSQL), Redis, MongoDB, Kafka, GraphQL, Elasticsearch/OpenSearch, AWS S3

**Languages with distributed trace context propagation:** Go, Node.js, Python, NGINX, PHP

> **K8s Engineer's Translation:** OBI is to distributed tracing what Hubble is to network flows — zero-configuration visibility. The difference is layer: Hubble sees L4 TCP/UDP flows; OBI sees L7 protocol semantics (HTTP method, SQL query, Kafka topic) without touching the application binary.

```yaml
# obi-daemonset.yaml
# Image: ghcr.io/open-telemetry/opentelemetry-ebpf-instrumentation/beyla (verify tag at release page)
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: obi
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: obi
  template:
    metadata:
      labels:
        app: obi
    spec:
      hostPID: true
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      tolerations:
        - operator: Exists           # run on all nodes including control-plane
      containers:
        - name: obi
          # Replace <tag> with the current release from the OBI GitHub releases page
          image: ghcr.io/open-telemetry/opentelemetry-ebpf-instrumentation/beyla:<tag>
          securityContext:
            privileged: true
            capabilities:
              add: [SYS_ADMIN, SYS_PTRACE, NET_RAW]
          env:
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://otel-collector.monitoring:4317"
            - name: BEYLA_OPEN_PORT           # instrument processes listening on this port
              value: "80,443,8080,8443"
            - name: BEYLA_DISCOVERY_SERVICES
              value: "true"                   # auto-discover K8s services
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "k8s.cluster.name=prod"
          volumeMounts:
            - name: kernel-debug
              mountPath: /sys/kernel/debug
      volumes:
        - name: kernel-debug
          hostPath:
            path: /sys/kernel/debug
```

```bash
kubectl apply -f obi-daemonset.yaml

# Verify OBI is running and exporting spans
kubectl logs -n monitoring -l app=obi --tail=20
# expect: "Starting Beyla" + "Sending spans to otel-collector.monitoring:4317"

# View L7 spans in Tempo via Grafana:
# Grafana → Explore → Tempo → Search → Service=your-service → see HTTP spans
```

---

### 10.3 K8s Operator + Instrumentation CRD

The [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator) adds two CRDs:

| CRD | Purpose |
|-----|---------|
| `OpenTelemetryCollector` | Declarative Collector deployment managed by the operator |
| `Instrumentation` | Auto-inject OTel SDK into pods by namespace or annotation |

**Install the operator:**

```bash
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
# expect: CRDs installed, operator pod running in opentelemetry-operator-system namespace

kubectl get crds | grep opentelemetry
# expect:
#   instrumentations.opentelemetry.io
#   opentelemetrycollectors.opentelemetry.io
```

**Deploy a Collector via CRD** (operator manages pods, services, config reload):

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: cluster-collector
  namespace: monitoring
spec:
  mode: deployment   # or: daemonset, sidecar, statefulset
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
    processors:
      batch: {}
    exporters:
      otlp/tempo:
        endpoint: http://tempo:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp/tempo]
```

**Auto-inject SDK with Instrumentation CRD** — no code change, no restart:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: auto-inject
  namespace: default
spec:
  exporter:
    endpoint: http://cluster-collector-collector.monitoring:4317
  propagators:
    - tracecontext
    - baggage
  python:
    env:
      - name: OTEL_LOGS_EXPORTER
        value: otlp
  java:
    env:
      - name: OTEL_METRICS_EXPORTER
        value: otlp
```

```bash
# Annotate a pod to inject Python SDK (no code change, no image rebuild):
kubectl annotate pod my-python-pod \
  instrumentation.opentelemetry.io/inject-python="true"

# Or annotate a Deployment to inject Java SDK into all pods:
kubectl patch deployment my-java-app -p \
  '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-java":"true"}}}}}'

# expect: pod restarts; initContainer injects the OTel Java agent JAR
# JAVA_TOOL_OPTIONS=-javaagent:/otel-auto-instrumentation-java/javaagent.jar set automatically
```

**Annotation-based Collector discovery** (no ConfigMap edit when new services are deployed):

```yaml
# Add to any pod that exposes Prometheus metrics via /metrics:
metadata:
  annotations:
    io.opentelemetry.discovery.metrics/enabled: "true"
    io.opentelemetry.discovery.metrics/scraper: "nginx"   # receiver type
    io.opentelemetry.discovery.metrics/port: "9113"
```

The Collector's receiver creator detects this annotation and instantiates an nginx receiver targeting that pod's port automatically.

---

### 10.4 Cilium Hubble OTLP Export

Cilium 1.15+ can export Hubble flow records directly as OTLP spans to any OTel Collector. Each L4 flow becomes a span with network semantic convention attributes.

```bash
# Enable Hubble OTLP export via Helm (Cilium 1.15+):
helm upgrade cilium cilium/cilium \
  --reuse-values \
  --namespace kube-system \
  --set hubble.export.opentelemetry.enabled=true \
  --set hubble.export.opentelemetry.endpoint="otel-collector.monitoring:4317"

# Verify spans are flowing:
kubectl logs -n kube-system -l k8s-app=hubble-relay --tail=20 | grep -i otlp
# expect: "OTLP export started" + span count incrementing
```

**What each Hubble OTLP span contains:**

| Span attribute | Value | Semantic convention |
|----------------|-------|---------------------|
| `span.name` | `TCP FORWARDED` / `TCP DROPPED` | Hubble verdict |
| `network.transport` | `tcp` / `udp` | Stable |
| `network.peer.address` | Destination pod IP | Stable |
| `network.peer.port` | Destination port | Stable |
| `source.workload.name` | Kubernetes pod name (source) | Cilium extension |
| `destination.workload.name` | Kubernetes pod name (dest) | Cilium extension |
| `network.type` | `ipv4` / `ipv6` | Stable |
| `network.connection.state` | `established` / `syn_sent` | RC |

```mermaid
sequenceDiagram
    participant HUB as Hubble Relay
    participant COL as OTel Collector
    participant TEMPO as Grafana Tempo
    participant ENG as Engineer (Grafana)

    HUB->>COL: OTLP/gRPC — L4 flow as span
    Note over HUB,COL: 1 flow record = 1 span<br>src/dst pod IP + verdict + attrs
    COL->>COL: transform processor<br>(drop health-check flows, enrich with K8s labels)
    COL->>TEMPO: OTLP — stored span
    ENG->>TEMPO: query: service=cilium, dropped=true
    TEMPO-->>ENG: trace showing which pod pairs had drops + at what time
```

---

### 10.5 Network Semantic Conventions

OTel defines a stable set of attribute names for network telemetry. Using these names ensures interoperability between OBI spans, Hubble spans, and backend queries.

| Attribute | Stability | Example value | Notes |
|-----------|-----------|---------------|-------|
| `network.local.address` | **Stable** | `10.0.1.5` | Source IP |
| `network.local.port` | **Stable** | `8080` | Source port |
| `network.peer.address` | **Stable** | `10.0.2.3` | Destination IP |
| `network.peer.port` | **Stable** | `443` | Destination port |
| `network.protocol.name` | **Stable** | `tcp` | L4 protocol |
| `network.protocol.version` | **Stable** | `1.1` | HTTP/TLS version |
| `network.transport` | **Stable** | `tcp` | Transport layer |
| `network.type` | **Stable** | `ipv4` | IP version |
| `network.connection.state` | RC | `established` | TCP state |
| `network.interface.name` | RC | `eth0` | NIC name |
| `network.io.direction` | RC | `receive` | Traffic direction |
| `network.peer.as.number` | Experimental | `64512` | BGP ASN — see [Lesson 06](06-bgp-fundamentals.md) |
| `network.peer.as.organization` | Experimental | `Cloudflare` | BGP peer org name |
| `network.local.as.number` | Experimental | `65000` | Local BGP ASN |

> **Note on PII:** `network.local.mac.address`, `network.peer.mac.address`, and `network.carrier.*` attributes are Experimental and carry PII warnings — do not emit to externally-accessible backends without scrubbing.

---

### 10.6 OTTL — Transform and Filter at the Collector

OTTL (OpenTelemetry Transformation Language) reached v1 stable in 2026. It is used in the `transform` and `filter` processors to manipulate any telemetry signal before export — without touching application code.

**Common network-engineering use cases:**

```yaml
# otel-collector-config-with-ottl.yaml
processors:
  # 1. Drop high-cardinality attributes that explode metric cardinality
  transform/drop_cardinality:
    trace_statements:
      - context: span
        statements:
          - delete_key(attributes, "http.url")       # full URL — too many unique values
          - delete_key(attributes, "db.statement")   # SQL text — PII + cardinality

  # 2. Rename network attributes to match your internal naming convention
  transform/rename_net:
    trace_statements:
      - context: span
        statements:
          - set(attributes["dst_ip"], attributes["network.peer.address"])
          - set(attributes["dst_port"], attributes["network.peer.port"])

  # 3. Drop health-check and liveness probe spans entirely
  filter/drop_healthchecks:
    traces:
      span:
        - 'attributes["http.target"] == "/healthz"'
        - 'attributes["http.target"] == "/readyz"'
        - 'attributes["http.target"] == "/metrics"'

  # 4. Keep only DROPPED Hubble flows (ignore FORWARDED for storage cost)
  filter/hubble_drops_only:
    traces:
      span:
        - 'name != "TCP DROPPED" and name != "UDP DROPPED"'

  batch:
    timeout: 1s

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors:
        - transform/drop_cardinality
        - transform/rename_net
        - filter/drop_healthchecks
        - batch
      exporters: [otlp/tempo]
    traces/hubble:
      receivers: [otlp]
      processors:
        - filter/hubble_drops_only
        - batch
      exporters: [otlp/tempo]
```

```bash
# Validate OTTL config before deploy:
otelcol validate --config=otel-collector-config-with-ottl.yaml
# expect: "Config is valid" — catches syntax errors in OTTL statements

# Common OTTL functions:
# set(target, value)              — assign a value
# delete_key(map, key)            — remove an attribute
# keep_keys(map, [key1, key2])    — drop all but listed keys
# truncate_all(map, limit)        — truncate all string values to limit bytes
# replace_match(target, pattern, replacement) — regex replace
```

---

### See Also

| Lesson | Relevance |
|--------|-----------|
| [Lesson 10 — eBPF and XDP](10-ebpf-xdp.md) | How OBI hooks into the kernel — eBPF program types used by zero-code instrumentation |
| [Lesson 12 — Cilium CNI and eBPF Dataplane](12-cilium-cni-ebpf.md) | Hubble architecture and how flow records are generated before OTLP export |
| [Lesson 21 — Service Mesh with Istio](21-service-mesh-istio.md) | OTel sidecar instrumentation as an alternative to OBI for Envoy-proxied services |
| [Lesson 39 — Network Incident Management, SLOs, and RCA](39-network-incident-management-slo-rca.md) | Full OTel + eBPF stack for SLO tracking and root-cause analysis in production |

---

## Check Your Understanding

1. **[Concept question]** Why does the L1-to-L7 troubleshooting methodology require confirming each layer before moving up, rather than starting at the Kubernetes service layer where the symptom is visible?

   <details><summary>Answer</summary>

   Higher-layer Kubernetes components (Services, NetworkPolicies, kube-proxy) depend on lower-layer correctness — if a route is missing or a veth pair is not wired to the OVS bridge, no amount of Kubernetes-level fixes will restore connectivity. Starting at L1/L2 (interface up, veth connected) and L3 (route present, ip_forward enabled) rules out the most fundamental issues before you spend time debugging iptables rules or Kubernetes endpoints that are actually fine. The golden rule is: confirm each layer is working before moving up, so you stop at the first layer that fails.

   </details>

2. **[Scenario question]** DNS lookups from a pod occasionally time out with exactly a 5-second delay. CoreDNS pods are running and healthy. What two root causes should you check first?

   <details><summary>Answer</summary>

   The two most common causes of 5-second DNS timeouts in Kubernetes are: (1) conntrack table exhaustion — when the nf_conntrack table is full, new UDP connections (including DNS queries) are dropped silently and the client waits for the timeout; check with `dmesg | grep "nf_conntrack: table full"` and compare `nf_conntrack_count` to `nf_conntrack_max`. (2) The conntrack UDP race condition with parallel DNS queries on the same socket — the kernel can SNAT both A and AAAA queries to the same 5-tuple and drop one; check CoreDNS logs for `NXDOMAIN` or timeout patterns, and consider setting `ndots:3` or enabling NodeLocal DNSCache.

   </details>

3. **[Practical question]** What command would you run to watch all denied network flows across the entire cluster in real time?

   <details><summary>Answer</summary>

   ```bash
   hubble observe --verdict DROPPED --all-namespaces
   ```
   Each line shows the source and destination pod names, namespace, destination port, and drop reason (such as `POLICY_DENIED` or `UNSUPPORTED_L3_PROTOCOL`); use this output to identify which flows are being blocked and by what policy, then work down the stack with `cilium policy trace` or `tcpdump` if the reason is not a Kubernetes NetworkPolicy.

   </details>

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [Isovalent: Getting Started with Cilium](https://isovalent.com/labs/getting-started-with-cilium/) | Free | Use Hubble CLI and UI to inspect live traffic flows, identify drops, build service dependency maps |
| [Isovalent: Zero Trust Visibility](https://isovalent.com/labs/zero-trust-visibility/) | Free | Investigate connectivity issues and build service maps using Hubble Timescape |
| [Killercoda Playground](https://killercoda.com/) | Free | Run `ss -s`, `conntrack -L`, `tcpdump`, deploy netshoot pod for live packet capture |
| [iximiuz: Networking Challenges](https://labs.iximiuz.com/challenges) | Free | Real troubleshooting scenarios — broken network configs with automated pass/fail checking |

---

*End of Kubernetes Network Engineering — Network Foundations Course*

---

**← Previous:** [Lesson 23 — Network Security Hardening](23-network-security-hardening.md)   |   **Next:** [Lesson 25 — OpenShift Networking Overview](25-openshift-networking-overview.md)
