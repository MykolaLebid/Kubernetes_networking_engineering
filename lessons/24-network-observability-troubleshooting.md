# Lesson 24 — Network Observability and Troubleshooting

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** All previous lessons — this is the capstone  
> **Duration:** ~3 hours

---

## Why This Matters

The best-designed network still needs to be debugged. This final lesson is a practitioner's reference — a systematic methodology and toolkit for diagnosing any network problem in Kubernetes, from "pod can't reach a service" to "latency spiked by 100ms."

---

## 1. Systematic Troubleshooting Methodology

Work from the bottom of the stack up:

```
L1/L2: Physical / Link — is the NIC up? is the interface up?
  ↓
L3: IP — is the route correct? is ip_forward on? MTU ok?
  ↓
L4: TCP/UDP — is conntrack full? iptables blocking?
  ↓
L7: Application — is DNS resolving? TLS cert valid?
  ↓
Kubernetes: Service exists? Endpoint healthy? NetworkPolicy denying?
  ↓
CNI: Pod IP assigned? veth wired? IPAM exhausted?
```

**The golden rule:** confirm each layer before moving up. Don't start at Kubernetes if you haven't confirmed the node NIC is up.

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

# In the same network namespace as a running pod:
kubectl debug -it <pod-name> --image=nicolaka/netshoot --target=<container-name>
```

---

## 3. Pod Connectivity Checklist

```bash
# SYMPTOM: Pod A cannot reach Pod B

# Step 1: Can Pod A reach its own gateway?
kubectl exec -it pod-a -- ping -c3 $(ip route | grep default | awk '{print $3}')

# Step 2: Can Pod A reach Pod B's IP directly?
POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
kubectl exec -it pod-a -- ping -c3 $POD_B_IP
# If fail → routing or NetworkPolicy issue

# Step 3: Is there a NetworkPolicy blocking traffic?
# Check policies selecting pod-a (egress) and pod-b (ingress)
kubectl get networkpolicy -n default -o yaml | grep -A10 "podSelector"
# Use Cilium policy trace:
cilium policy trace --src-pod default/pod-a --dst-pod default/pod-b --dport 80

# Step 4: Is the route present?
NODE=$(kubectl get pod pod-b -o jsonpath='{.spec.nodeName}')
# SSH to node
ssh $NODE
ip route get $POD_B_IP

# Step 5: Cross-node — is VXLAN/BGP working?
# Check CNI status
calicoctl node status   # or: cilium status

# Step 6: Packet capture
# On pod-b's node:
tcpdump -i any -n host $POD_B_IP
```

---

## 4. Service Connectivity Checklist

```bash
# SYMPTOM: Pod cannot reach Service

# Step 1: Does the service exist?
kubectl get svc web -n default

# Step 2: Does it have endpoints?
kubectl get endpoints web -n default
# No endpoints → selector doesn't match pods, or pods aren't ready

# Step 3: Is the DNS name resolving?
kubectl exec -it pod-a -- nslookup web.default.svc.cluster.local
kubectl exec -it pod-a -- nslookup web   # short name

# Step 4: Is the ClusterIP reachable?
CLUSTER_IP=$(kubectl get svc web -o jsonpath='{.spec.clusterIP}')
kubectl exec -it pod-a -- curl -v http://$CLUSTER_IP:80

# Step 5: Are iptables DNAT rules present?
iptables -t nat -L KUBE-SERVICES -n | grep $CLUSTER_IP

# Step 6: Is kube-proxy running and healthy?
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-proxy | tail -20
```

---

## 5. DNS Troubleshooting

```bash
# SYMPTOM: DNS lookups failing or slow

# Step 1: Can pod reach CoreDNS?
kubectl exec -it pod-a -- nc -vzu 10.96.0.10 53

# Step 2: Does a simple lookup work?
kubectl exec -it pod-a -- nslookup kubernetes.default.svc.cluster.local

# Step 3: Enable CoreDNS query logging
kubectl edit cm -n kube-system coredns
# Add: log  (inside the .:53 { block)
kubectl rollout restart deployment -n kube-system coredns

# Watch queries
kubectl logs -n kube-system -l k8s-app=kube-dns -f | grep -v "NOERROR"

# Step 4: Check ndots behavior
kubectl exec -it pod-a -- cat /etc/resolv.conf
# high ndots:5 → many fallback queries for external names

# Step 5: Check CoreDNS metrics
kubectl port-forward -n kube-system svc/kube-dns 9153:9153 &
curl -s http://localhost:9153/metrics | grep coredns_dns_request_duration

# Step 6: Check for conntrack UDP race condition
# (symptom: 5-second DNS timeouts)
dmesg | grep "nf_conntrack: table full"
sysctl net.netfilter.nf_conntrack_count
sysctl net.netfilter.nf_conntrack_max
```

---

## 6. Latency Investigation

```bash
# SYMPTOM: High latency between pods

# Step 1: Baseline measurement
kubectl exec -it pod-a -- \
  for i in $(seq 10); do curl -w "%{time_total}\n" -o /dev/null -s http://web; done

# Step 2: Check for packet loss
kubectl exec -it pod-a -- ping -c100 -f $POD_B_IP
# "%" column shows packet loss

# Step 3: MTU mismatch (causes fragmentation → latency)
kubectl exec -it pod-a -- ping -M do -s 1422 $POD_B_IP  # VXLAN
# If "Message too long" → MTU mismatch

# Check effective MTU
kubectl exec -it pod-a -- ip link show eth0 | grep mtu

# Step 4: CPU throttling on pods (affects packet processing)
kubectl top pod pod-a
kubectl describe pod pod-a | grep -A5 "Limits\|Requests"

# Step 5: conntrack contention
# High conntrack lookup latency on busy nodes:
cat /proc/net/stat/nf_conntrack

# Step 6: Node CPU for network interrupts
# On node:
watch -n1 'cat /proc/interrupts | grep -E "eth0|mlx5"'
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

# Capture inside pod
kubectl exec -it pod-a -- tcpdump -i eth0 -n -w /tmp/capture.pcap
# Copy out:
kubectl cp pod-a:/tmp/capture.pcap ./pod-a.pcap

# ksniff — kubectl plugin for pod packet capture
kubectl sniff pod-a -n default -o ./pod-a.pcap

# Capture VXLAN encapsulated traffic (between nodes)
tcpdump -i eth0 -n udp port 4789 -w /tmp/vxlan.pcap

# View in Wireshark
# wireshark ./pod-a.pcap
# or analyze with tshark:
tshark -r pod-a.pcap -T fields -e frame.number -e ip.src -e ip.dst -e tcp.dstport
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

# Watch denied flows (policy violations)
hubble observe --verdict DROPPED --all-namespaces

# Flow for specific pod
hubble observe --from-pod default/frontend --to-pod default/backend

# Count flows per destination
hubble observe --all-namespaces -o json | \
  jq -r '.flow | .destination.namespace + "/" + .destination.pod_name' | \
  sort | uniq -c | sort -rn | head -20

# HTTP flows
hubble observe --protocol http --all-namespaces | head -20

# Service connectivity map (Hubble UI)
cilium hubble ui
```

---

## 9. Key Metrics to Monitor

```bash
# Kubernetes network metrics (from kube-state-metrics + node-exporter)
# In Prometheus/Grafana:

# Node network throughput
rate(node_network_receive_bytes_total{device="eth0"}[5m])
rate(node_network_transmit_bytes_total{device="eth0"}[5m])

# Network errors
rate(node_network_receive_errs_total[5m])
rate(node_network_transmit_errs_total[5m])

# conntrack usage
node_nf_conntrack_entries / node_nf_conntrack_entries_limit

# DNS query rate
rate(coredns_dns_requests_total[5m])

# DNS error rate
rate(coredns_dns_responses_total{rcode!="NOERROR"}[5m])

# kube-proxy sync latency
rate(kubeproxy_sync_proxy_rules_duration_seconds_bucket[5m])
```

---

## 10. Troubleshooting Quick Reference

| Symptom | First Check | Tool |
|---------|------------|------|
| Pod can't ping pod | NetworkPolicy, IP route, MTU | `ping`, `ip route`, `cilium policy trace` |
| Pod can't reach service | Endpoints, kube-proxy, DNS | `kubectl get ep`, `iptables`, `nslookup` |
| DNS timeout | CoreDNS, conntrack, ndots | `kubectl logs coredns`, `nslookup` |
| Intermittent connections | conntrack table full, MTU | `dmesg`, `ping -M do` |
| High latency | MTU, CPU throttling, kube-proxy | `ping -f`, `iperf3` |
| LB pending | CCM, MetalLB, cloud IAM | `kubectl describe svc`, CCM logs |
| BGP not established | TCP/179, ASN config, BIRD | `calicoctl node status`, `telnet :179` |
| VXLAN drops | UDP/4789 blocked, MTU | `tcpdump udp port 4789`, `iptables -L` |

---

## 11. Summary and Graduation

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

---

*End of Kubernetes Network Engineering — Network Foundations Course*
