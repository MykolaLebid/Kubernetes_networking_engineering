# Lesson 32 — AWS Hybrid and Multi-Cluster Networking

> **Track:** AWS Networking  
> **Prerequisites:** [Lesson 22 — Multi-Cluster Networking](22-multi-cluster-networking.md), [Lesson 30 — AWS VPC Design](30-aws-vpc-design.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl multi-context)
kubectl config get-contexts
aws eks list-clusters --output table 2>/dev/null || echo "Configure AWS CLI first"

# Terminal 2 — Mac (aws CLI — inspect Transit Gateway if present)
aws ec2 describe-transit-gateways \
  --query 'TransitGateways[*].[TransitGatewayId,State,Description]' \
  --output table 2>/dev/null || echo "No Transit Gateways or AWS CLI not configured"
```

---

## 1. Connecting Multiple EKS Clusters

### VPC Peering (simplest, same region or cross-region)

```bash
# Create VPC peering between cluster A VPC and cluster B VPC
aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-cluster-a \
  --peer-vpc-id vpc-cluster-b \
  --peer-region us-west-2   # omit for same region

# Accept the peering request
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id pcx-xxxxx

# Update route tables in both VPCs
aws ec2 create-route \
  --route-table-id rtb-cluster-a \
  --destination-cidr-block 10.1.0.0/16 \     # cluster B VPC CIDR
  --vpc-peering-connection-id pcx-xxxxx

aws ec2 create-route \
  --route-table-id rtb-cluster-b \
  --destination-cidr-block 10.0.0.0/16 \     # cluster A VPC CIDR
  --vpc-peering-connection-id pcx-xxxxx
```

Pod CIDRs must not overlap. With VPC peering + VPC CNI, pods can reach each other directly by IP.

**Limitations:** no transitive routing (A↔B, B↔C, but not A↔C via B).

---

### Transit Gateway (hub-and-spoke, recommended for 3+ VPCs)

```bash
# Create Transit Gateway
aws ec2 create-transit-gateway \
  --description "EKS multi-cluster TGW" \
  --options DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable

# Attach VPCs to TGW
aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id tgw-xxxxx \
  --vpc-id vpc-cluster-a \
  --subnet-ids subnet-a1 subnet-a2

aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id tgw-xxxxx \
  --vpc-id vpc-cluster-b \
  --subnet-ids subnet-b1 subnet-b2

# Add routes in each VPC pointing to TGW for other clusters
aws ec2 create-route \
  --route-table-id rtb-cluster-a-private \
  --destination-cidr-block 10.1.0.0/16 \
  --transit-gateway-id tgw-xxxxx
```

TGW supports transitive routing: A↔B, B↔C, A↔C all work.

```
AWS Transit Gateway: Hub-and-Spoke vs VPC Peering

VPC Peering (full mesh — does NOT scale):
  VPC A ──────── VPC B
    │  ╲        ╱  │
    │    ╲    ╱    │
    │      ╲╱      │   N VPCs = N×(N-1)/2 peering connections
    │      ╱╲      │   4 VPCs = 6 connections
    │    ╱    ╲    │   10 VPCs = 45 connections
  VPC C ──────── VPC D   No transitive routing (A↔B, B↔C ≠ A↔C)

Transit Gateway (hub-and-spoke — scales to 5000 attachments):

                    ┌────────────────────────────┐
                    │      Transit Gateway        │
                    │   Route Table (default):    │
                    │   10.0.0.0/8 → all VPCs    │
                    └──┬──────┬──────┬──────┬────┘
                       │      │      │      │
                  ┌────┘  ┌───┘  ┌──┘  ┌───┘
                  │       │      │     │
             ┌────▼─┐ ┌───▼─┐ ┌──▼──┐ ┌▼────────────┐
             │EKS-1 │ │EKS-2│ │EKS-3│ │On-Premises  │
             │10.0. │ │10.1.│ │10.2.│ │Direct Connect│
             │0/16  │ │0/16 │ │0/16 │ │192.168.0/16 │
             └──────┘ └─────┘ └─────┘ └─────────────┘
             N VPCs = N TGW attachments (not N² peering)

EKS pod routing via TGW (VPC CNI — no overlay needed):
  Pod in EKS-1 (10.0.1.5) → Pod in EKS-2 (10.1.2.8)
  Route: 10.1.0.0/16 → tgw-attach-EKS-2 → ENI in EKS-2 node → pod
```

---

## 2. Cross-Cluster Service Discovery

After VPC peering or TGW, pods can reach each other by IP. But DNS discovery still needs work.

### Option A: Shared CoreDNS (stub zones)

```bash
# In cluster A's CoreDNS, forward cluster-b.local queries to cluster B's DNS
kubectl edit cm -n kube-system coredns
```

```
cluster-b.local:53 {
    forward . 172.30.0.10   # cluster B's kube-dns ClusterIP
    cache 30
}
```

```bash
# For this to work, cluster A nodes must be able to reach cluster B's kube-dns
# → ensure security groups allow UDP/TCP 53 between clusters
```

### Option B: ExternalDNS + Route53

```bash
# Install ExternalDNS in both clusters
# It creates Route53 records for Services and Ingresses

helm install external-dns bitnami/external-dns \
  --set provider=aws \
  --set aws.region=us-east-1 \
  --set domainFilters[0]=cluster-a.example.com \
  --set policy=sync

# Services with annotation get DNS records:
kubectl annotate svc web \
  external-dns.alpha.kubernetes.io/hostname=web.cluster-a.example.com
```

### Option C: AWS VPC Lattice (new, managed service mesh)

```bash
# VPC Lattice provides service-to-service connectivity without VPC peering
# Install AWS Gateway API Controller
helm install aws-gateway-controller \
  oci://public.ecr.aws/aws-samples/aws-gateway-api-controller \
  -n aws-application-networking-system

# Create a ServiceNetwork (spans VPCs/clusters)
kubectl apply -f - <<EOF
apiVersion: application-networking.k8s.aws/v1beta1
kind: VpcLatticeServiceNetwork
metadata:
  name: my-service-network
EOF

# Services registered in the network are reachable cross-cluster
```

---

## 3. On-Premises to EKS (Hybrid)

### AWS Direct Connect

```
On-prem data center
    │
    └── Direct Connect (dedicated fiber, 1/10/100 Gbps)
            │
            └── AWS Direct Connect Gateway
                    │
                    └── Transit Gateway
                            │
                            └── EKS VPC
```

```bash
# Create a Transit Virtual Interface
aws directconnect create-transit-virtual-interface \
  --connection-id dxcon-xxxxx \
  --new-transit-virtual-interface \
    virtualInterfaceName=to-tgw,\
    vlan=100,\
    asn=65000,\
    mtu=9001,\
    transitGatewayId=tgw-xxxxx

# BGP peers automatically for route exchange
# On-prem router advertises: 192.168.0.0/16 (on-prem CIDR)
# AWS TGW advertises: 10.0.0.0/8 (VPC CIDRs)
```

### Site-to-Site VPN (simpler, over internet)

```bash
# Create Customer Gateway (your on-prem router)
aws ec2 create-customer-gateway \
  --type ipsec.1 \
  --public-ip 203.0.113.1 \  # on-prem public IP
  --bgp-asn 65001

# Create VPN Gateway and attach to VPC
aws ec2 create-vpn-gateway --type ipsec.1
aws ec2 attach-vpn-gateway \
  --vpn-gateway-id vgw-xxxxx \
  --vpc-id vpc-eks

# Create VPN connection
aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id cgw-xxxxx \
  --vpn-gateway-id vgw-xxxxx \
  --options StaticRoutesOnly=false   # use BGP

# Download VPN config for your on-prem router
aws ec2 describe-vpn-connections \
  --vpn-connection-ids vpn-xxxxx \
  --query 'VpnConnections[0].CustomerGatewayConfiguration'
```

---

## 4. EKS Anywhere (On-Premises EKS)

EKS Anywhere brings EKS to your data center with the same tooling.

```bash
# Install eksctl-anywhere plugin
brew install aws/tap/eks-anywhere

# Create a cluster spec
eksctl anywhere generate clusterconfig my-cluster \
  --provider vsphere > cluster.yaml  # or: baremetal, docker, nutanix

# Review and deploy
eksctl anywhere create cluster -f cluster.yaml

# Networking with EKS Anywhere:
# - Uses Cilium as default CNI
# - Full BGP support for bare-metal
# - Same kubectl/eksctl experience as cloud EKS
```

---

## 5. Cilium Cluster Mesh on EKS

```bash
# Enable Cluster Mesh on EKS clusters
# (after replacing VPC CNI with Cilium)
cilium clustermesh enable \
  --service-type LoadBalancer \
  --context eks-cluster-a

cilium clustermesh enable \
  --service-type LoadBalancer \
  --context eks-cluster-b

# Connect the clusters
cilium clustermesh connect \
  --source-context eks-cluster-a \
  --destination-context eks-cluster-b

# Verify
cilium clustermesh status --context eks-cluster-a
```

---

## 6. Cross-Account EKS Access

```bash
# Share Transit Gateway across accounts
aws ram create-resource-share \
  --name tgw-share \
  --resource-arns arn:aws:ec2:us-east-1:ACCOUNT-A:transit-gateway/tgw-xxxxx \
  --principals ACCOUNT-B-ID

# In account B, accept the share
aws ram accept-resource-share-invitation \
  --resource-share-invitation-arn arn:aws:ram:...

# Attach account B's VPC to the shared TGW
aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id tgw-xxxxx \  # from account A
  --vpc-id vpc-cluster-b-accountB \
  --subnet-ids subnet-xxxxx
```

---

## 7. Troubleshooting Hybrid Connectivity

```bash
# 1. Can a pod reach on-prem IP?
kubectl run -it --rm test --image=nicolaka/netshoot -- \
  ping -c3 192.168.1.10

# 2. Is the route present on the node?
# (SSH to node or use SSM)
ip route get 192.168.1.10
# Should show route via TGW/VGW ENI

# 3. VPC Flow Logs — check if packets are being rejected
aws logs filter-log-events \
  --log-group-name /aws/vpc/flowlogs \
  --filter-pattern "[..., action=REJECT]"

# 4. Direct Connect — is BGP up?
aws directconnect describe-virtual-interfaces \
  --query 'virtualInterfaces[?virtualInterfaceState==`available`]'

# 5. VPN — are tunnels up?
aws ec2 describe-vpn-connections \
  --query 'VpnConnections[0].VgwTelemetry'
# Status: UP for both tunnels
```

---

## 8. Summary

| Solution | Use Case | Routing |
|----------|---------|---------|
| VPC Peering | 2–3 clusters, same/cross region | Direct, no transit |
| Transit Gateway | 3+ clusters, hub-and-spoke | Transitive |
| VPC Lattice | Service mesh across VPCs/accounts | Managed, L7-aware |
| Direct Connect | On-prem to AWS, production | BGP, dedicated |
| VPN | On-prem to AWS, dev/backup | BGP or static, over internet |
| EKS Anywhere | On-prem EKS | Same as bare-metal (Lesson 07) |

---

## Online Resources

| Resource | Cost | What you practice |
|----------|------|-------------------|
| [AWS EKS Workshop](https://www.eksworkshop.com/) | Free workshop (~$3 AWS cost) | Transit Gateway connectivity, VPC peering between EKS clusters, Direct Connect simulation |
| [AWS Skill Builder — Networking](https://skillbuilder.aws/) | Free (AWS account required) | Transit Gateway, VPC peering, and hybrid networking simulated labs |
| [Submariner Quickstart](https://submariner.io/getting-started/quickstart/) | Free | Connect two local kind clusters — a free stand-in for practicing cross-cluster pod routing concepts without AWS cost |

---

*End of AWS Networking Track*

**See also:** [Lesson 22 — Multi-Cluster Networking](22-multi-cluster-networking.md) for Cilium Cluster Mesh and Submariner details.
