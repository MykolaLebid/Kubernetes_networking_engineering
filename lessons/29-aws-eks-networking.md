# Lesson 29 — AWS EKS Networking Deep Dive

> **Track:** AWS Networking  
> **Prerequisites:** [Lesson 08 — Cloud Provider Networking](08-cloud-provider-networking.md), [Lesson 09 — CNI](09-cni-specification.md)  
> **Duration:** ~3 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl + aws CLI)
kubectl get nodes -o wide
kubectl get ds -n kube-system aws-node   # VPC CNI daemonset

# Terminal 2 — Mac (aws CLI)
aws sts get-caller-identity
aws ec2 describe-network-interfaces \
  --filters "Name=description,Values=aws-K8s-*" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,PrivateIpAddresses[*].PrivateIpAddress]' \
  --output table 2>/dev/null || echo "Configure AWS CLI with EKS cluster credentials"
```

---

## 1. EKS Architecture

```
AWS Account
└── VPC (10.0.0.0/16)
    ├── Public Subnets  (10.0.1.0/24, 10.0.2.0/24)  ← NLB, NAT GW
    └── Private Subnets (10.0.10.0/24, 10.0.11.0/24) ← EC2 nodes
         └── EC2 Worker Nodes
              └── ENIs with secondary IPs (pod IPs)
                   └── aws-vpc-cni assigns pod IPs from ENI secondary IPs
```

**Control Plane:** Managed by AWS — lives in AWS-owned VPC, connected to your VPC via cross-account ENI.

---

## 2. AWS VPC CNI (amazon-vpc-cni-k8s)

The default CNI for EKS. Pods get **real VPC IP addresses** from EC2 ENI secondary IPs — no overlay needed.

```bash
# Check VPC CNI version
kubectl get ds -n kube-system aws-node -o jsonpath='{.spec.template.spec.containers[0].image}'
# 602401143452.dkr.ecr.us-east-1.amazonaws.com/amazon-k8s-cni:v1.18.x

# View VPC CNI configuration
kubectl get cm -n kube-system amazon-vpc-cni -o yaml

# Check IPAMD (IP Address Management Daemon) logs
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-node | tail -30
```

### How pod IP assignment works:

```
Node boots → aws-node IPAMD starts
  ↓
IPAMD calls EC2 API: attach secondary ENIs to this instance
  ↓
IPAMD calls EC2 API: assign secondary private IPs to each ENI
  ↓
IPAMD maintains a warm pool of available IPs
  ↓
Pod scheduled → CNI plugin requests IP from IPAMD
  ↓
IPAMD assigns one secondary IP → becomes the pod IP
  ↓
No NAT/overlay needed — pod IP is a real VPC IP
```

```
AWS VPC CNI: ENI Secondary IP Assignment

  EC2 Node (m5.large: 3 ENIs × 10 secondary IPs)

  ┌─────────────────────────────────────────────────────────────────┐
  │  EC2 Worker Node (172.31.1.10)                                  │
  │                                                                  │
  │  Primary ENI (eth0)          Secondary ENI (eth1)               │
  │  ┌───────────────────┐       ┌───────────────────┐              │
  │  │ Primary IP:       │       │ Primary IP:       │              │
  │  │ 172.31.1.10       │       │ 172.31.1.50       │              │
  │  │                   │       │                   │              │
  │  │ Secondary IPs:    │       │ Secondary IPs:    │              │
  │  │ 172.31.1.11 ──► Pod A    │ 172.31.1.51 ──► Pod D           │
  │  │ 172.31.1.12 ──► Pod B    │ 172.31.1.52 ──► Pod E           │
  │  │ 172.31.1.13 ──► Pod C    │ 172.31.1.53 ──► Pod F           │
  │  └───────────────────┘       └───────────────────┘              │
  │                                                                  │
  │  Pod IP = real VPC IP (no overlay, no NAT for pod-to-pod)       │
  │  aws-node IPAMD maintains warm pool of pre-assigned IPs         │
  └─────────────────────────────────────────────────────────────────┘

  Prefix delegation (ENABLE_PREFIX_DELEGATION=true):
  Instead of 10 secondary IPs per ENI → 1 /28 prefix = 16 IPs
  m5.large with prefix delegation: 3 ENIs × 16 IPs = 48 pods (was 29)
```

---

## 3. Pod Density Limits

Each EC2 instance type has a maximum number of ENIs and IPs per ENI:

```bash
# Check current node's ENI limits
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
INSTANCE_TYPE=$(kubectl get node $NODE_NAME \
  -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}')
echo "Instance type: $INSTANCE_TYPE"

# View how many pods are running vs maximum
kubectl describe node $NODE_NAME | grep -E "Capacity|Allocatable" -A10
# pods: 29  (m5.large = 3 ENIs × 10 IPs - 1 per ENI for node = 29 max)
```

Formula: `(ENIs × IPs_per_ENI) - ENIs = max_pods`

| Instance | ENIs | IPs/ENI | Max Pods |
|----------|------|---------|---------|
| t3.small | 3 | 4 | 11 |
| m5.large | 3 | 10 | 29 |
| m5.xlarge | 4 | 15 | 58 |
| m5.4xlarge | 8 | 30 | 234 |

### Prefix Delegation (increases pod density significantly)
```bash
# Enable prefix delegation — assigns /28 blocks instead of individual IPs
kubectl set env ds aws-node \
  -n kube-system \
  ENABLE_PREFIX_DELEGATION=true \
  WARM_PREFIX_TARGET=1

# After enabling, m5.large gets 3 ENIs × 10 prefixes × 16 IPs = 480 IPs
```

---

## 4. Security Groups for Pods

By default all pods on a node share the node's Security Group. With Security Groups for Pods, each pod can have its own SG.

```bash
# Enable Security Groups for Pods (requires trunk ENI mode)
kubectl set env ds aws-node \
  -n kube-system \
  ENABLE_POD_ENI=true

# Restart node group to activate trunk ENI
```

```yaml
# SecurityGroupPolicy — assign SG to specific pods
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: db-sg-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: database-client
  securityGroups:
    groupIds:
      - sg-0123456789abcdef0   # SG that allows DB access
```

```bash
# Verify pod has the right SG
aws ec2 describe-network-interfaces \
  --filters "Name=private-ip-address,Values=$(kubectl get pod <pod> -o jsonpath='{.status.podIP}')" \
  --query 'NetworkInterfaces[0].Groups'
```

---

## 5. VPC CNI Network Policies

Since v1.14, AWS VPC CNI includes a built-in network policy controller using eBPF.

```bash
# Enable network policy controller
kubectl set env ds aws-node \
  -n kube-system \
  ENABLE_NETWORK_POLICY_CONTROLLER=true

# Standard Kubernetes NetworkPolicy resources are enforced by VPC CNI eBPF
kubectl apply -f network-policy.yaml

# View eBPF programs loaded by VPC CNI
kubectl exec -n kube-system -l k8s-app=aws-node -- \
  bpftool prog list | grep aws
```

---

## 6. EKS Node Networking

```bash
# View ENIs on a node
NODE_IP=$(kubectl get node $NODE_NAME \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=$NODE_IP" \
  --query 'Reservations[0].Instances[0].NetworkInterfaces[*].{ENI:NetworkInterfaceId,IPs:PrivateIpAddresses[*].PrivateIpAddress}'

# View routes on the node (shows /32 routes per pod)
# SSH to node via SSM or bastion:
ssh ec2-user@$NODE_IP
ip route show | grep -v docker | head -30
# 10.0.10.5 dev eth0 scope link  ← pod IP host route
# 10.0.10.6 dev eth1 scope link
```

```bash
# Check which ENI a pod IP is assigned to
kubectl get pod <pod> -o jsonpath='{.status.podIP}'
# → then find in AWS Console: EC2 → Network Interfaces → filter by IP
```

---

## 7. EKS with Custom CNI (Calico/Cilium)

You can replace or augment the VPC CNI with Calico or Cilium.

```bash
# Option 1: Calico NetworkPolicy only (keep VPC CNI for pod IPs)
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml

# Option 2: Cilium replacing VPC CNI entirely
# Requires disabling aws-vpc-cni first
kubectl -n kube-system delete daemonset aws-node

helm install cilium cilium/cilium \
  --namespace kube-system \
  --set eni.enabled=true \
  --set ipam.mode=eni \
  --set egressMasqueradeInterfaces=eth0 \
  --set tunnel=disabled
```

---

## 8. EKS Cluster Networking Checklist

```bash
# 1. Nodes in private subnets?
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
# IPs should be in private range (10.x, 172.16-31.x, 192.168.x)

# 2. Source/Destination Check disabled?
aws ec2 describe-instance-attribute \
  --instance-id <id> \
  --attribute sourceDestCheck
# "Value": false  ← correct

# 3. Pod CIDRs not overlapping with VPC?
kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'

# 4. CoreDNS healthy?
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 5. VPC CNI warm pool healthy?
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-node | \
  grep -E "WARN|ERROR|ipamd"

# 6. Can pods reach AWS services?
kubectl run -it --rm test --image=amazonlinux -- \
  aws s3 ls  # uses IAM role via IRSA
```

---

## 9. IRSA — IAM Roles for Service Accounts

Pods need AWS API access without storing credentials. IRSA uses OIDC to map K8s service accounts to IAM roles.

```bash
# Associate OIDC provider with cluster
eksctl utils associate-iam-oidc-provider \
  --cluster my-cluster --approve

# Create IAM role for a service account
eksctl create iamserviceaccount \
  --name s3-reader \
  --namespace production \
  --cluster my-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve

# Pod uses the service account
spec:
  serviceAccountName: s3-reader
  # AWS_WEB_IDENTITY_TOKEN_FILE is auto-injected
```

---

## 10. Summary

| Concept | Detail |
|---------|--------|
| Pod IP model | Real VPC IPs from ENI secondary IPs |
| Pod density | Limited by instance ENI/IP limits — use prefix delegation |
| Pod SGs | SecurityGroupPolicy CRD for per-pod security groups |
| Network Policy | VPC CNI eBPF (v1.14+) or Calico overlay |
| IAM | IRSA: service account → IAM role (no stored credentials) |
| Encryption | In transit via TLS; pod-to-pod: add Calico/Cilium WireGuard |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [AWS EKS Workshop](https://www.eksworkshop.com/) | Free workshop (~$3 AWS cost, clean up after) | ENI secondary IPs, VPC CNI configuration, prefix delegation, Security Groups for Pods — mirrors this lesson end-to-end |
| [AWS Skill Builder — Amazon EKS](https://skillbuilder.aws/) | Free (AWS account required) | Official AWS simulated labs for EKS networking with no live infrastructure cost |
| [Amazon EKS Best Practices Guide — Networking](https://aws.github.io/aws-eks-best-practices/networking/index/) | Free | Deep reference on VPC CNI design, pod density, custom networking — read alongside this lesson |

---

**Next:** [Lesson 30 — AWS VPC Design for Kubernetes](30-aws-vpc-design.md)
