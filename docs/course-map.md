# Course Map

Visual dependency graph of all 34 lessons. Follow the arrows to understand prerequisites.

---

## Lesson Dependency Graph

```mermaid
flowchart TD
    01["01\nLinux Networking\nFundamentals"]
    02["02\nIP Routing &\nForwarding"]
    03["03\niptables &\nNetfilter"]
    04["04\nNetwork Namespaces\nDeep Dive"]
    05["05\nVXLAN & Overlay\nNetworks"]
    06["06\nBGP\nFundamentals"]
    07["07\nBare Metal\nInfrastructure"]
    08["08\nCloud Provider\nNetworking"]
    09["09\nCNI\nSpecification"]
    10["10\neBPF\nand XDP"]
    11["11\nCalico CNI\nDeep Dive"]
    12["12\nCilium CNI\neBPF Dataplane"]
    13["13\nK8s Services\nkube-proxy"]
    14["14\nCoreDNS\nService Discovery"]
    15["15\nIPv6\nDual-Stack"]
    16["16\nNetwork\nPolicies"]
    17["17\nIngress\nControllers"]
    18["18\nGateway\nAPI"]
    19["19\nMetalLB\nkube-vip"]
    20["20\nCloud\nLoad Balancers"]
    21["21\nService Mesh\nIstio"]
    22["22\nMulti-Cluster\nNetworking"]
    23["23\nNetwork Security\nHardening"]
    24["24\nNetwork\nObservability"]
    25["25\nOpenShift\nOverview"]
    26["26\nOVN-\nKubernetes"]
    27["27\nOpenShift Routes\nHAProxy"]
    28["28\nOpenShift\nEgressIP"]
    29["29\nAWS EKS\nNetworking"]
    30["30\nAWS VPC\nDesign"]
    31["31\nAWS LB\nController"]
    32["32\nAWS Hybrid\nMulti-Cluster"]
    33["33\nArgoCD\nGitOps"]
    34["34\nAI Platform\nNetworking"]

    01 --> 02
    01 --> 03
    01 --> 04
    02 --> 05
    02 --> 06
    03 --> 09
    03 --> 13
    04 --> 05
    04 --> 09
    06 --> 07
    06 --> 11
    07 --> 07
    08 --> 09
    08 --> 29
    09 --> 10
    09 --> 11
    09 --> 12
    10 --> 11
    10 --> 12
    11 --> 23
    12 --> 22
    12 --> 23
    12 --> 24
    13 --> 14
    13 --> 17
    13 --> 19
    14 --> 15
    14 --> 16
    15 --> 16
    16 --> 22
    16 --> 23
    17 --> 18
    17 --> 20
    18 --> 20
    19 --> 20
    21 --> 22
    21 --> 23
    22 --> 32
    22 --> 33
    23 --> 24
    25 --> 26
    25 --> 27
    25 --> 28
    29 --> 30
    29 --> 31
    30 --> 31
    31 --> 32
    33 --> 34

    style 01 fill:#1565C0,color:#fff
    style 02 fill:#1565C0,color:#fff
    style 03 fill:#1565C0,color:#fff
    style 04 fill:#1565C0,color:#fff
    style 05 fill:#1565C0,color:#fff
    style 06 fill:#1565C0,color:#fff
    style 07 fill:#1565C0,color:#fff
    style 08 fill:#1976D2,color:#fff
    style 09 fill:#1976D2,color:#fff
    style 10 fill:#1976D2,color:#fff
    style 11 fill:#1976D2,color:#fff
    style 12 fill:#1976D2,color:#fff
    style 13 fill:#0288D1,color:#fff
    style 14 fill:#0288D1,color:#fff
    style 15 fill:#0288D1,color:#fff
    style 16 fill:#0288D1,color:#fff
    style 17 fill:#00838F,color:#fff
    style 18 fill:#00838F,color:#fff
    style 19 fill:#00838F,color:#fff
    style 20 fill:#00838F,color:#fff
    style 21 fill:#2E7D32,color:#fff
    style 22 fill:#2E7D32,color:#fff
    style 23 fill:#2E7D32,color:#fff
    style 24 fill:#2E7D32,color:#fff
    style 25 fill:#C62828,color:#fff
    style 26 fill:#C62828,color:#fff
    style 27 fill:#C62828,color:#fff
    style 28 fill:#C62828,color:#fff
    style 29 fill:#E65100,color:#fff
    style 30 fill:#E65100,color:#fff
    style 31 fill:#E65100,color:#fff
    style 32 fill:#E65100,color:#fff
    style 33 fill:#4527A0,color:#fff
    style 34 fill:#880E4F,color:#fff
```

---

## Track Overview

| Track | Lessons | Focus |
|-------|---------|-------|
| A — Linux Foundations | 01–07 | Kernel primitives every Kubernetes network is built on |
| B — CNI Plugins & eBPF | 08–12 | How pods get network interfaces and IPs |
| C — Kubernetes Networking | 13–16 | Services, DNS, dual-stack, network policy |
| D — Ingress & Load Balancing | 17–20 | External traffic into the cluster |
| E — Advanced Topics | 21–24 | Istio, multi-cluster, security hardening, observability |
| F — OpenShift | 25–28 | OVN-Kubernetes, Routes, EgressIP |
| G — AWS | 29–32 | EKS-specific networking and hybrid connectivity |
| H — GitOps | 33 | ArgoCD sync waves for network config delivery |
| I — AI Platform | 34 | RDMA, SR-IOV, rail topology, GPU cluster networking |

---

## Minimum Learning Paths

### CKA Exam Focus (Lessons 01–24)
`01 → 02 → 03 → 04 → 09 → 13 → 14 → 16 → 17 → 21 → 23 → 24`

### OpenShift Engineer
`01 → 03 → 09 → 13 → 16 → 25 → 26 → 27 → 28`

### AWS/EKS Specialist
`01 → 03 → 08 → 09 → 13 → 16 → 20 → 29 → 30 → 31 → 32`

### AI/HPC Platform Engineer
`01 → 05 → 07 → 09 → 10 → 12 → 34`
