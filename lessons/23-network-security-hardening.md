# Lesson 23 — Network Security Hardening

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 14 — Network Policies](14-network-policies.md), [Lesson 19 — Istio](19-service-mesh-istio.md)  
> **Duration:** ~2.5 hours

---

## Why This Matters

The default Kubernetes cluster is not secure out of the box: all pods can reach all pods, all pods can reach the internet, and traffic is unencrypted. Network security hardening closes these gaps. It's required for PCI-DSS, HIPAA, SOC 2, and any production workload handling sensitive data.

---

## 1. The Threat Model

```
Threats to address:
  1. Lateral movement         — compromised pod attacks other pods
  2. Exfiltration             — pod sends data to attacker-controlled server
  3. Credential theft         — pod reaches metadata API, gets cloud credentials
  4. Eavesdropping            — network traffic captured on shared infrastructure
  5. Privilege escalation     — pod uses hostNetwork to bypass pod-level controls
  6. Supply chain             — malicious image calls home
```

---

## 2. Default Deny Network Policies

Start with deny-all and explicitly allow required traffic.

```yaml
# Namespace-level default deny
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
---
# Allow only DNS egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
---
# Allow health check probes from kube-system
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-healthchecks
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
```

---

## 3. Block Cloud Metadata API

The cloud metadata API (169.254.169.254) exposes credentials and configuration. Block it from pods.

```yaml
# Block access to cloud metadata service
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-metadata-api
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
              - 169.254.169.254/32   # AWS/GCP/Azure metadata
              - 169.254.170.2/32     # AWS ECS metadata
```

```bash
# Verify block works
kubectl run -it --rm test --image=nicolaka/netshoot -- \
  curl -m 3 http://169.254.169.254/latest/meta-data/
# Should timeout
```

---

## 4. Encryption in Transit

### Cilium WireGuard
```bash
helm upgrade cilium cilium/cilium --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set encryption.nodeEncryption=true   # encrypt node-to-node too

# Verify encryption
cilium encrypt status
# Encryption: Wireguard
# Keys in use: 1
```

### Calico WireGuard
```bash
kubectl patch felixconfiguration default \
  --type='merge' \
  -p '{"spec":{"wireguardEnabled":true}}'

# Verify
kubectl get node <node> -o yaml | grep wireguard
calicoctl node status | grep WireGuard
```

### Istio mTLS
```yaml
# Enforce strict mTLS cluster-wide
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system   # applies to all namespaces
spec:
  mtls:
    mode: STRICT
```

---

## 5. Egress Control with FQDN Policies

Cilium allows restricting outbound traffic to specific domain names.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-external-apis
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: worker
  egress:
    - toFQDNs:
        - matchName: "api.github.com"
        - matchPattern: "*.amazonaws.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

Calico also supports DNS-based policy in Enterprise edition.

---

## 6. Pod Security and Network Interaction

Kubernetes PodSecurity Admission enforces security at the pod level, which complements network controls.

```yaml
# Apply baseline security to a namespace
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest

# Restricted: prevents hostNetwork, hostPID, privileged
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted
```

**Network-relevant pod spec hardening:**
```yaml
spec:
  hostNetwork: false       # don't share host network namespace
  hostPID: false           # don't share host PID namespace
  securityContext:
    runAsNonRoot: true
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["NET_BIND_SERVICE"]  # only if binding ports < 1024
```

---

## 7. Audit Logging for Network Events

```bash
# Cilium flow audit (all denied flows)
hubble observe --verdict DROPPED --all-namespaces -o json | \
  jq '{src: .flow.source.pod_name, dst: .flow.destination.pod_name,
       dport: .flow.l4.TCP.destination_port, verdict: .flow.verdict}'

# Tetragon network audit
kubectl exec -n kube-system ds/tetragon -- \
  tetra getevents --event-types PROCESS_ACCEPT,PROCESS_CONNECT -o json

# kube-apiserver audit log — network policy changes
kubectl get events --all-namespaces | grep NetworkPolicy
```

---

## 8. Network Security Checklist

```bash
# 1. Default deny policies in all namespaces
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  count=$(kubectl get networkpolicy -n $ns 2>/dev/null | grep deny | wc -l)
  echo "$ns: $count deny policies"
done

# 2. Pod → metadata API is blocked
kubectl run -it --rm meta-test --image=curlimages/curl -- \
  curl -m 3 http://169.254.169.254/

# 3. Encryption is active
cilium encrypt status   # for Cilium/WireGuard

# 4. mTLS is enforced (Istio)
istioctl authn tls-check --all-namespaces 2>/dev/null | grep CONFLICT

# 5. No hostNetwork pods (except system components)
kubectl get pods --all-namespaces \
  -o json | jq '.items[] | select(.spec.hostNetwork == true) |
    .metadata.namespace + "/" + .metadata.name'

# 6. No pods with excessive capabilities
kubectl get pods --all-namespaces \
  -o json | jq '.items[].spec.containers[].securityContext.capabilities.add // empty'

# 7. Egress to internet is controlled
kubectl run -it --rm egress-test --image=nicolaka/netshoot -- \
  curl -m 5 https://ifconfig.me
```

---

## 9. Compliance Reference

| Requirement | Kubernetes Control |
|-------------|-------------------|
| PCI-DSS 1.2 | NetworkPolicy: segment cardholder data environment |
| PCI-DSS 4.1 | Istio/Calico mTLS: encrypt cardholder data in transit |
| HIPAA | NetworkPolicy + mTLS: isolate PHI workloads |
| SOC 2 | Audit logs: Hubble + Tetragon for network events |
| CIS Benchmark | Default deny policies, no hostNetwork for user pods |

```bash
# CIS Kubernetes Benchmark network checks
# 5.3.1 Ensure network policies are set (default deny)
# 5.3.2 Ensure all namespaces have network policies

# Automated scan with kube-bench
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs -f job.kube-bench | grep -A3 "5.3"
```

---

## 10. Summary

| Control | Tool | What It Prevents |
|---------|------|----------------|
| Default deny | NetworkPolicy | Lateral movement |
| Metadata block | NetworkPolicy (ipBlock except) | Credential theft |
| FQDN egress | Cilium CiliumNetworkPolicy | Exfiltration |
| Encryption | WireGuard / mTLS | Eavesdropping |
| Pod security | PodSecurity Admission | hostNetwork bypass |
| Audit | Hubble / Tetragon | Detecting incidents |

---

**Next:** [Lesson 24 — Network Observability and Troubleshooting](24-network-observability-troubleshooting.md)
