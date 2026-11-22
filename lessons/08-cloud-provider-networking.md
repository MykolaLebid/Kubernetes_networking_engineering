# Lesson 08 — Cloud Provider Networking Basics

> **Track:** Network Foundation — Cloud Provider  
> **Prerequisites:** [Lesson 02 — IP Routing and Forwarding](02-ip-routing-and-forwarding.md)  
> **Duration:** ~3 hours

---

## Practice Setup

```bash
# Terminal 1 — kubectl (Mac)
kubectl get nodes -o wide
kubectl get pods -A -o wide | head -20

# Terminal 2 — cloud CLI (optional, Mac)
kubectl get cm -n kube-system amazon-vpc-cni -o yaml 2>/dev/null || echo "Not on AWS EKS"
kubectl get cm -n kube-system ip-masq-agent -o yaml 2>/dev/null || echo "Not on GKE"
```

---

## Why This Matters

Cloud providers abstract physical networking behind software-defined networking (SDN). EKS, GKE, and AKS each integrate Kubernetes with their VPC/VNet in unique ways that affect pod IPs, load balancer behavior, security groups, and cross-cluster connectivity. Understanding these models is essential for designing reliable, secure, and cost-effective cloud-native Kubernetes deployments.

---

## 1. The SDN Abstraction

Cloud VPCs implement routing in software, not on physical switches. This means:
- Routes are enforced by the hypervisor/network fabric — you don't configure ToR switches
- IP-in-IP or VXLAN tunnels may already be used underneath (invisible to you)
- Routing changes propagate in seconds (API calls), not minutes (BGP convergence)
- Security is enforced at the VM NIC level (Security Groups, NACLs)

---

## 2. AWS Networking for Kubernetes

### VPC Architecture
```
VPC: 10.0.0.0/16
  ├── Subnet (us-east-1a): 10.0.1.0/24
  │     ├── EC2 node: 10.0.1.10  (eth0 = primary ENI)
  │     └── EC2 node: 10.0.1.11
  ├── Subnet (us-east-1b): 10.0.2.0/24
  └── Internet Gateway + NAT Gateway
```

### AWS VPC CNI (amazon-vpc-cni-k8s)
Pods get **real VPC IPs** from secondary ENI private IPs.

```
Node (m5.xlarge): 2 ENIs × 15 IPs/ENI = 30 pod IPs max
                                         (limits vary by instance type)
```

```bash
# Check ENIs and secondary IPs on a node
aws ec2 describe-instances --instance-ids <id> \
  --query 'Reservations[0].Instances[0].NetworkInterfaces'

# View pod IPs assigned via VPC CNI
kubectl get pods -o wide -A | head -20

# Check AWS VPC CNI version
kubectl get ds -n kube-system aws-node -o jsonpath='{.spec.template.spec.containers[0].image}'

# VPC CNI configuration
kubectl get cm -n kube-system amazon-vpc-cni -o yaml
```

**Source/Destination Check** must be disabled (EKS does this automatically):
```bash
aws ec2 modify-instance-attribute \
  --instance-id <id> \
  --no-source-dest-check
```

### AWS Security Groups
Security Groups are stateful firewalls at the ENI level.

```bash
# Check which SGs are on a node
aws ec2 describe-instances --instance-ids <id> \
  --query 'Reservations[0].Instances[0].SecurityGroups'

# EKS creates these SGs automatically:
# - Cluster SG (control plane ↔ nodes)
# - Node SG (node ↔ node, pod ↔ pod)
```

For pod-level security groups (Security Groups for Pods):
```yaml
# SecurityGroupPolicy CRD (requires VPC CNI trunk ENI mode)
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: web-sg-policy
spec:
  podSelector:
    matchLabels:
      app: web
  securityGroups:
    groupIds:
      - sg-0123456789abcdef0
```

### AWS Load Balancer Integration
```yaml
# NLB (Network Load Balancer) — L4
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

```yaml
# ALB (Application Load Balancer) — L7, via AWS Load Balancer Controller
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
```

---

## 3. GCP Networking for Kubernetes

### VPC Architecture
GCP VPC is **global** (no regional boundary) and uses custom-mode subnets.

```
VPC: k8s-vpc
  ├── Subnet (us-central1): 10.0.0.0/20  — node IPs
  │     └── Secondary IP range (pods):   10.100.0.0/14
  │     └── Secondary IP range (svcs):   10.200.0.0/20
  └── Cloud Router + Cloud NAT
```

### GKE Networking
GKE uses **Alias IP ranges** — each node gets a /24 from the pod range, and pod IPs are real VPC addresses.

```bash
# View node pod CIDR allocations
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'

# GKE Dataplane v2 (uses Cilium eBPF under the hood)
kubectl get cm -n kube-system cilium-config -o yaml 2>/dev/null

# Check Dataplane version
gcloud container clusters describe <cluster> --format='value(networkConfig.datapathProvider)'
# ADVANCED_DATAPATH = Dataplane v2
# LEGACY_DATAPATH = iptables kube-proxy
```

### GCP Firewall Rules
GCP firewall rules are **global**, applied at the VPC level, not per-instance.

```bash
# View firewall rules for the cluster
gcloud compute firewall-rules list --filter="name~gke-"

# GKE auto-creates:
# gke-<cluster>-master      — kubelet API access from control plane
# gke-<cluster>-vms         — node ↔ node traffic
# gke-<cluster>-inkubelet   — control plane to nodes
```

### GCP Load Balancer Integration
```yaml
# External passthrough NLB (default)
service:
  type: LoadBalancer

# Internal L4
service:
  type: LoadBalancer
  annotations:
    networking.gke.io/load-balancer-type: "Internal"

# Global L7 via GKE Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "gce"
```

---

## 4. Azure Networking for Kubernetes

### VNet Architecture
```
VNet: 10.0.0.0/8
  ├── Subnet (nodeSubnet):  10.240.0.0/16  — nodes + pods (Azure CNI)
  └── Subnet (svcSubnet):   10.0.0.0/16    — services
```

### Azure CNI
Two modes:

**Azure CNI (classic):** Pods get IPs from the VNet subnet.
```bash
# Each node pre-allocates pod IPs from the subnet
az aks show --resource-group rg --name aks \
  --query networkProfile.podCidr
```

**Azure CNI Overlay:** Pods get IPs from a separate overlay CIDR (less VNet IP exhaustion).
```bash
az aks show --resource-group rg --name aks \
  --query networkProfile.networkMode
# overlay
```

### NSG (Network Security Group)
NSGs filter traffic at the subnet or NIC level.

```bash
# View NSG rules applied to AKS nodes
az network nsg rule list \
  --resource-group <node-resource-group> \
  --nsg-name <nsg-name>
```

### Azure Load Balancer Integration
```yaml
# External LoadBalancer (Azure Standard LB)
service:
  type: LoadBalancer

# Internal
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-load-balancer-internal-subnet: "internal-subnet"
```

---

## 5. Cross-Provider Comparison

| Feature | AWS (EKS) | GCP (GKE) | Azure (AKS) |
|---------|-----------|-----------|-------------|
| Pod IP model | VPC secondary IPs (ENI) | Alias IP ranges | VNet IPs (Azure CNI) |
| Pod IP limit per node | Instance type dependent | Node /24 from range | Subnet size dependent |
| eBPF dataplane | Possible (Cilium on EKS) | Dataplane v2 (default) | Cilium option |
| L4 LB | NLB | Passthrough NLB | Azure Standard LB |
| L7 LB | ALB (Controller) | Cloud LB (GCE Ingress) | App Gateway Ingress |
| Security model | Security Groups (ENI) | VPC Firewall Rules | NSG |
| Node-to-node | VPC routing | VPC routing | VNet routing |

---

## 6. Networking Gotchas per Provider

### AWS
```bash
# Gotcha 1: ENI limit → pod density limit
# m5.large: 3 ENIs × 10 IPs = 30 pods max (minus 1 per ENI for node)
# Check limits: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html

# Gotcha 2: Prefix delegation (increases pod density)
kubectl set env ds -n kube-system aws-node ENABLE_PREFIX_DELEGATION=true

# Gotcha 3: externalTrafficPolicy=Local required for client IP preservation with NLB
```

### GCP
```bash
# Gotcha 1: Default firewalls allow all internal traffic — add deny rules for segmentation
# Gotcha 2: Alias IP ranges must be sized before cluster creation (can't shrink)
# Gotcha 3: GKE uses MASQUERADE for pod egress by default
kubectl get configmap -n kube-system ip-masq-agent -o yaml
```

### Azure
```bash
# Gotcha 1: Azure CNI classic exhausts VNet IPs quickly
# 110 pods/node × 100 nodes = 11,000 IPs needed in subnet

# Gotcha 2: AKS requires pre-planned subnet for Azure CNI
# Use Overlay mode for large clusters

# Gotcha 3: NSG rules are managed by AKS — manual edits get overwritten
```

---

## 7. Hands-On: Inspect Cloud Cluster Networking

```bash
# Any cloud cluster — trace a pod's IP back to the cloud resource

# Step 1: Get pod IP
kubectl get pod <pod> -o jsonpath='{.status.podIP}'

# Step 2: Find which node
kubectl get pod <pod> -o jsonpath='{.spec.nodeName}'

# Step 3: AWS — find the ENI that owns this secondary IP
NODE_IP=$(kubectl get node <node> -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
aws ec2 describe-network-interfaces \
  --filters "Name=private-ip-address,Values=<pod-ip>" \
  --query 'NetworkInterfaces[0].{ENI:NetworkInterfaceId,Node:PrivateIpAddress}'

# Step 4: Verify security groups allow the traffic
aws ec2 describe-network-interface-attribute \
  --network-interface-id <eni-id> \
  --attribute groupSet
```

---

## 8. Summary

| Provider | Key Concept |
|----------|------------|
| AWS EKS | VPC CNI gives pods real ENI IPs; Security Groups at ENI level |
| GCP GKE | Alias IP ranges; Dataplane v2 uses Cilium eBPF |
| Azure AKS | Azure CNI Overlay recommended for large clusters; NSG at subnet |
| All | Cloud LBs integrate via CCM (Cloud Controller Manager) annotations |

---

## Online Resources

| Resource | Type | What you practice |
|----------|------|-------------------|
| [AWS EKS Workshop](https://www.eksworkshop.com/) | Free workshop (small AWS cost ~$3) | Hands-on VPC CNI, ENI secondary IPs, Security Groups for Pods — the AWS half of this lesson |
| [AWS Skill Builder — Amazon EKS](https://skillbuilder.aws/) | Free (simulated labs) | Official AWS labs for EKS networking with no AWS account cost for simulations |
| [Killercoda Playground](https://killercoda.com/) | Free playground | Inspect CNI configs and pod networking on a local cluster |

---

**Next:** [Lesson 09 — CNI Specification and Plugin Architecture](09-cni-specification.md)
