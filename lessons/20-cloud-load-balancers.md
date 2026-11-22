# Lesson 18 — Cloud Provider Load Balancers

> **Track:** Network Foundation — Cloud Provider  
> **Prerequisites:** [Lesson 08 — Cloud Provider Networking](08-cloud-provider-networking.md), [Lesson 12 — Services](13-kubernetes-services-kube-proxy.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl)
kubectl get svc -A --field-selector spec.type=LoadBalancer
kubectl describe svc <your-lb-svc> | grep -E "LoadBalancer|Ingress|Annotations"

# Terminal 2 — cloud CLI (optional)
aws elb describe-load-balancers 2>/dev/null | jq '.LoadBalancerDescriptions[].LoadBalancerName' || \
  echo "Configure AWS CLI or use GCP/Azure equivalent"
```

---

## Why This Matters

Cloud load balancers are provisioned automatically through the Cloud Controller Manager (CCM) when you create a `type: LoadBalancer` service. Each cloud provider has multiple LB types with different capabilities, pricing models, and traffic modes. Choosing the right one and configuring it correctly impacts performance, cost, and security.

---

## 1. How Cloud LBs Are Provisioned

```
kubectl apply service (type: LoadBalancer)
     ↓
kube-controller-manager → cloud controller manager (CCM)
     ↓
CCM calls cloud API (AWS/GCP/Azure)
     ↓
Cloud creates LB, assigns External IP
     ↓
CCM updates Service.status.loadBalancer.ingress
     ↓
kubectl get svc shows EXTERNAL-IP
```

```bash
# Track provisioning
kubectl get svc web -w
# EXTERNAL-IP: <pending> → 203.0.113.100

# CCM logs
kubectl logs -n kube-system -l app=cloud-controller-manager
```

---

## 2. AWS Load Balancers

### Classic Load Balancer (CLB) — legacy
Created by default before the AWS Load Balancer Controller.

### Network Load Balancer (NLB) — L4
Recommended for TCP/UDP. Very high throughput, static IPs.

```yaml
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"   # pod IP targets
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "TCP"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "traffic-port"
    # Cross-zone load balancing
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    # Preserve client IP
    service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "preserve_client_ip.enabled=true"
```

### Application Load Balancer (ALB) — L7
Created via the AWS Load Balancer Controller (Ingress resource).

```yaml
# Install AWS LBC
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=my-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123:role/alb-role
```

```yaml
# ALB Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip      # pod-level targets
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123:certificate/xxx
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/group.name: "shared-alb"  # share one ALB across Ingresses
```

### Target Types

| Target Type | Traffic Path | Use Case |
|-------------|-------------|---------|
| `instance` | LB → NodePort → pod | Default, simpler |
| `ip` | LB → pod IP directly | Lower latency, requires VPC CNI |

---

## 3. GCP Load Balancers

### External Passthrough NLB (default)
```yaml
# Default LoadBalancer service
spec:
  type: LoadBalancer

# Restrict access to specific CIDRs
spec:
  loadBalancerSourceRanges:
    - 10.0.0.0/8
    - 203.0.113.0/24
```

### Internal L4 (ILB)
```yaml
metadata:
  annotations:
    networking.gke.io/load-balancer-type: "Internal"
    # Optional: specify subnet
    networking.gke.io/internal-load-balancer-subnet: "my-subnet"
```

### External Global L7 (GCE Ingress)
```yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.global-static-ip-name: "my-static-ip"
    networking.gke.io/managed-certificates: "my-ssl-cert"
```

```bash
# Create a managed SSL certificate
kubectl apply -f - <<EOF
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: my-ssl-cert
spec:
  domains:
    - web.example.com
EOF
```

### GKE BackendConfig — Health Checks and CDN
```yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: web-backend-config
spec:
  healthCheck:
    requestPath: /healthz
    port: 8080
    type: HTTP
  cdn:
    enabled: true
    cachePolicy:
      includeHost: true
      includeProtocol: true
      includeQueryString: false
  connectionDraining:
    drainingTimeoutSec: 60
```

---

## 4. Azure Load Balancers

### Standard External LB
```yaml
# Default
spec:
  type: LoadBalancer
```

### Internal LB
```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-load-balancer-internal-subnet: "my-internal-subnet"
```

### Standard LB annotations
```yaml
annotations:
  # Static IP from public IP resource
  service.beta.kubernetes.io/azure-pip-name: "my-public-ip"

  # DNS label
  service.beta.kubernetes.io/azure-dns-label-name: "my-service"

  # Health probe
  service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: "/healthz"
  service.beta.kubernetes.io/azure-load-balancer-health-probe-protocol: "https"

  # Idle timeout
  service.beta.kubernetes.io/azure-idle-timeout-in-minutes: "30"

  # Share LB across services
  service.beta.kubernetes.io/azure-shared-securityrule: "true"
```

### App Gateway for Containers (AKS Gateway API)
```bash
az aks create --name my-aks \
  --enable-oidc-issuer \
  --enable-workload-identity

# Install ALB controller
helm install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller \
  --namespace azure-alb-system
```

---

## 5. Cross-Provider Comparison

| Feature | AWS NLB | GCP NLB | Azure SLB |
|---------|---------|---------|-----------|
| Protocol | TCP/UDP | TCP/UDP/ICMP | TCP/UDP |
| Static IP | Elastic IP | Static IP resource | Public IP resource |
| Cross-zone | Configurable | Auto | Auto |
| Client IP preserve | Yes (ip target) | Yes (ExternalTrafficPolicy:Local) | Yes (ExternalTrafficPolicy:Local) |
| Proxy protocol | Yes | No | No |
| DDoS protection | AWS Shield (Basic free) | Cloud Armor (paid) | Azure DDoS (paid) |
| Internal LB | Yes | Yes | Yes |

---

## 6. ExternalTrafficPolicy and Source IP

```yaml
spec:
  externalTrafficPolicy: Local   # preserve source IP, only pods on receiving node
  # vs:
  externalTrafficPolicy: Cluster # any pod reachable, source IP SNATed to node IP
```

```bash
# With Local: check if traffic will be unbalanced (nodes without pods get no traffic)
kubectl get pods -o wide -l app=web   # see which nodes have pods

# Cloud LB health check must work correctly with Local policy
# The LB health-checks the NodePort; nodes without ready pods return unhealthy
```

---

## 7. Debugging Cloud LBs

```bash
# Step 1: Is the EXTERNAL-IP assigned?
kubectl get svc web -w

# Step 2: Check cloud events
kubectl describe svc web
# Events: Normal  EnsuredLoadBalancer  Successfully ensured load balancer
# Events: Warning FailedToEnsure       ...  ← look here on failure

# Step 3: CCM logs
kubectl logs -n kube-system -l k8s-app=cloud-controller-manager

# Step 4: AWS — check the LB in console/CLI
aws elbv2 describe-load-balancers --names <cluster>-<namespace>-<service>

# Step 5: GCP — check the forwarding rule
gcloud compute forwarding-rules list | grep <service-uid>

# Step 6: Azure — check the LB rule
az network lb list --resource-group <node-rg>

# Common issues:
# 1. IAM permissions missing (CCM can't create LB)
# 2. Subnet annotations missing (AKS internal LB needs subnet)
# 3. ExternalTrafficPolicy=Local + no pods on that node → health check fails
# 4. Security Group / Firewall not allowing health check probe IPs
# 5. Cloud provider account limits on LBs
```

---

## 8. Summary

| Provider | L4 LB | L7 LB | Internal |
|----------|--------|--------|---------|
| AWS EKS | NLB | ALB (LBC controller) | NLB internal |
| GCP GKE | Passthrough NLB | Cloud LB (GCE Ingress) | ILB |
| Azure AKS | Standard LB | App Gateway / AGIC | Internal SLB |
| Bare metal | MetalLB / kube-vip | NGINX/Traefik | Same (private pool) |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [AWS EKS Workshop](https://www.eksworkshop.com/) | Free workshop (~$3 AWS cost) | Deploy NLB and ALB via AWS Load Balancer Controller, configure annotations, test instance vs ip target mode |
| [AWS Skill Builder — Amazon EKS](https://skillbuilder.aws/) | Free (account required) | Official AWS simulated labs for EKS load balancing with no live AWS cost |
| [GKE Quickstart](https://cloud.google.com/kubernetes-engine/docs/quickstart) | Free tier (GCP free credits) | Deploy a GKE cluster with a LoadBalancer service and inspect the cloud LB created |

---

**Next:** [Lesson 21 — Service Mesh with Istio](21-service-mesh-istio.md)
