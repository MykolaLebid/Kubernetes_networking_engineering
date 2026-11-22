# Lesson 30 — AWS VPC Design for Kubernetes

> **Track:** AWS Networking  
> **Prerequisites:** [Lesson 29 — EKS Networking Deep Dive](29-aws-eks-networking.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (aws CLI)
aws sts get-caller-identity
aws ec2 describe-vpcs --query 'Vpcs[*].{ID:VpcId,CIDR:CidrBlock}' --output table

# Terminal 2 — Mac
# Find EKS-tagged subnets
aws ec2 describe-subnets \
  --query 'Subnets[?Tags[?Key==`kubernetes.io/role/elb`]].[SubnetId,CidrBlock,AvailabilityZone]' \
  --output table 2>/dev/null || echo "Configure AWS CLI first"
```

---

## 1. VPC Sizing for EKS

The most common mistake in EKS deployments is under-sizing the VPC and subnets. Plan for:

```
Pods:    each pod = 1 IP (VPC CNI)
Nodes:   each node = 1 IP per ENI attached
LBs:     each NLB/ALB = 1 IP per AZ
Services: no IPs (ClusterIP is virtual, not VPC-routable)
```

### IP Planning Formula

```
Required IPs = (nodes × 1) + (pods × 1) + (LBs × AZs × 1) + 20% buffer

Example: 50 nodes, 1500 pods, 10 LBs, 3 AZs
  = 50 + 1500 + (10 × 3) + 310 buffer
  = ~1890 IPs → need at least /21 (2046 IPs) per subnet
```

---

## 2. Recommended VPC Architecture

```
VPC: 10.0.0.0/16  (65,536 IPs)
│
├── Public Subnets (one per AZ)
│   ├── 10.0.0.0/24  us-east-1a  (254 IPs) ← NAT GW, ALB
│   ├── 10.0.1.0/24  us-east-1b
│   └── 10.0.2.0/24  us-east-1c
│
├── Private Subnets — Nodes + Pods (one per AZ)
│   ├── 10.0.10.0/22  us-east-1a  (1022 IPs) ← worker nodes + pods
│   ├── 10.0.14.0/22  us-east-1b
│   └── 10.0.18.0/22  us-east-1c
│
└── (Optional) Secondary CIDR for pods
    100.64.0.0/16  ← RFC 6598 "shared address space", avoids VPC exhaustion
```

```bash
# Create VPC with secondary CIDR for pods (avoids exhausting primary CIDR)
aws ec2 create-vpc --cidr-block 10.0.0.0/16
aws ec2 associate-vpc-cidr-block \
  --vpc-id vpc-xxxxx \
  --cidr-block 100.64.0.0/16

# Configure VPC CNI to use the secondary CIDR for pods
kubectl set env ds aws-node -n kube-system \
  AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true \
  ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone
```

---

## 3. Subnet Tags for EKS

EKS requires specific tags on subnets for auto-discovery:

```bash
# Tag private subnets for internal load balancers
aws ec2 create-tags \
  --resources subnet-xxxxx \
  --tags Key=kubernetes.io/cluster/my-cluster,Value=shared \
         Key=kubernetes.io/role/internal-elb,Value=1

# Tag public subnets for internet-facing load balancers
aws ec2 create-tags \
  --resources subnet-yyyyy \
  --tags Key=kubernetes.io/cluster/my-cluster,Value=shared \
         Key=kubernetes.io/role/elb,Value=1
```

Without these tags:
- LoadBalancer services fail to provision NLBs
- ALBs from the Load Balancer Controller fail to find subnets

---

## 4. Security Groups

EKS creates and manages several Security Groups:

```bash
# List EKS-managed security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:kubernetes.io/cluster/my-cluster,Values=owned" \
  --query 'SecurityGroups[*].{Name:GroupName,ID:GroupId}'
```

| SG | Purpose | Key Rules |
|----|---------|-----------|
| Cluster SG | Control plane ↔ nodes | Allow all within SG |
| Node SG | Node ↔ node traffic | Allow within SG |
| Additional node SGs | Custom rules | Your additions |

```bash
# Add custom rule: allow DB access from pods
aws ec2 authorize-security-group-ingress \
  --group-id sg-db-xxxxx \
  --protocol tcp \
  --port 5432 \
  --source-group sg-node-xxxxx  # allow from node SG
```

### Security Group Rules for Common Ports

```bash
# Allow VXLAN/Geneve (if using Cilium/Calico overlay)
aws ec2 authorize-security-group-ingress \
  --group-id sg-node-xxxxx \
  --protocol udp --port 4789 \  # VXLAN
  --source-group sg-node-xxxxx

# Allow BGP (if using Calico BGP)
aws ec2 authorize-security-group-ingress \
  --group-id sg-node-xxxxx \
  --protocol tcp --port 179 \
  --source-group sg-node-xxxxx

# Allow NodePort range
aws ec2 authorize-security-group-ingress \
  --group-id sg-node-xxxxx \
  --protocol tcp --port 30000-32767 \
  --cidr 10.0.0.0/8
```

---

## 5. Custom Networking — ENIConfig

When pods must use a different subnet than nodes (e.g., pod CIDR in a secondary subnet or AZ):

```yaml
# ENIConfig per AZ
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: us-east-1a       # must match AZ name
spec:
  subnet: subnet-pod-1a   # subnet for pod ENIs in this AZ
  securityGroups:
    - sg-pod-xxxxx
---
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: us-east-1b
spec:
  subnet: subnet-pod-1b
  securityGroups:
    - sg-pod-xxxxx
```

```bash
# Enable custom networking
kubectl set env ds aws-node -n kube-system \
  AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true \
  ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone

# Nodes automatically pick the right ENIConfig based on their AZ label
```

---

## 6. PrivateLink and VPC Endpoints

Pods accessing AWS services go via NAT Gateway by default (costly and adds latency). VPC Endpoints keep traffic in the VPC.

```bash
# Create S3 Gateway endpoint (free)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids rtb-xxxxx rtb-yyyyy

# Create ECR Interface endpoints (required for private clusters)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.us-east-1.ecr.api \
  --subnet-ids subnet-xxxxx \
  --security-group-ids sg-xxxxx \
  --private-dns-enabled

aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.us-east-1.ecr.dkr \
  --subnet-ids subnet-xxxxx \
  --security-group-ids sg-xxxxx \
  --private-dns-enabled

# Required endpoints for fully private EKS cluster:
# ec2, ecr.api, ecr.dkr, s3 (gateway), sts, elasticloadbalancing
```

---

## 7. EKS Fully Private Cluster

No public endpoint — control plane only reachable from within VPC:

```bash
# Create private cluster
aws eks create-cluster \
  --name private-cluster \
  --resources-vpc-config \
    subnetIds=subnet-xxxxx,subnet-yyyyy,\
    securityGroupIds=sg-xxxxx,\
    endpointPrivateAccess=true,\
    endpointPublicAccess=false

# Access requires VPN or Direct Connect or bastion
# Or use SSM Session Manager for node access
aws ssm start-session --target i-xxxxx
```

---

## 8. VPC Flow Logs for Kubernetes Debugging

```bash
# Enable VPC flow logs to CloudWatch
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs/my-cluster

# Query flow logs for a pod IP
aws logs filter-log-events \
  --log-group-name /aws/vpc/flowlogs/my-cluster \
  --filter-pattern "10.0.10.25"

# Useful CloudWatch Insights query
# fields @timestamp, srcAddr, dstAddr, dstPort, action
# | filter srcAddr = "10.0.10.25"
# | filter action = "REJECT"
# | sort @timestamp desc
# | limit 50
```

---

## 9. Network ACLs vs Security Groups

| | Security Groups | Network ACLs |
|--|----------------|--------------|
| Scope | ENI level | Subnet level |
| Stateful | Yes | No (must allow return traffic) |
| Default | Deny all inbound | Allow all |
| Rules | Allow only | Allow + Deny |
| EKS use | Primary control | Secondary, rarely needed |

```bash
# NACLs that commonly break EKS (stateless — must allow both directions):
# Allow ephemeral ports outbound (1024-65535) on return traffic
aws ec2 authorize-network-acl-entry \
  --network-acl-id acl-xxxxx \
  --rule-number 900 \
  --protocol tcp \
  --port-range From=1024,To=65535 \
  --cidr-block 0.0.0.0/0 \
  --egress \
  --rule-action allow
```

---

## 10. Summary

| Design Decision | Recommendation |
|----------------|---------------|
| VPC CIDR | /16 minimum; add /16 secondary for pods |
| Private subnet size | /22 per AZ (1022 IPs) minimum |
| Subnet tags | kubernetes.io/role/elb and internal-elb required |
| Pod density | Use prefix delegation for large clusters |
| AWS API access | VPC Endpoints for ECR, S3, STS, EC2 |
| Traffic visibility | VPC Flow Logs to CloudWatch |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [AWS EKS Workshop — VPC and Subnets](https://www.eksworkshop.com/) | Free workshop (~$3 AWS cost) | Create VPC with correct subnet tags, configure ENIConfig for custom networking, deploy to multi-AZ |
| [AWS Skill Builder — Amazon EKS](https://skillbuilder.aws/) | Free (AWS account required) | Subnet design labs for EKS without live infrastructure cost |
| [Amazon EKS Best Practices Guide — Networking](https://aws.github.io/aws-eks-best-practices/networking/index/) | Free | VPC CIDR planning, subnet sizing formulas, VPC endpoint design for EKS |
| [AWS VPC Subnet Calculator](https://network00.com/NetworkTools/IPv4SubnetCreator/) | Free browser tool | Plan your /22 subnets and pod CIDR ranges visually before applying |

---

**Next:** [Lesson 31 — AWS Load Balancer Controller Deep Dive](31-aws-load-balancer-controller.md)
