# Lesson 00 — Kubernetes Networking: Visual Overview

> **Track:** Orientation · **Prerequisites:** None · **Duration:** ~30 minutes (read-only)

> **Goal:** Build a complete mental picture of Kubernetes networking before touching a single command. Every diagram in this lesson maps directly to a later lesson — use it as a reference you return to throughout the course.

---

## How to Use This Lesson

Read this top-to-bottom once before starting Track A. The six diagrams progress from the inside out:

1. Kubernetes control/data plane split
2. Pod networking on a single node
3. Pod-to-pod traffic across nodes
4. CNI plugin comparison (Calico vs Cilium vs VPC CNI)
5. Service types and traffic paths
6. State-of-the-art 2026 dataplane (eBPF vs iptables)

Each diagram is self-contained. On a reMarkable or e-reader, zoom in on each one individually.

---

## 1. Kubernetes Architecture — Control Plane and Data Plane

Every Kubernetes cluster splits into two planes. The **control plane** decides what should happen; the **data plane** makes it happen.

```mermaid
flowchart TD
    subgraph CP["Control Plane (master nodes)"]
        API["kube-apiserver\nREST gateway\nAuthn/Authz/Admission"]
        ETCD["etcd\nDistributed KV store\nCluster state"]
        SCHED["kube-scheduler\nPod placement\nTopology / taints"]
        CM["kube-controller-manager\nNode / ReplicaSet /\nEndpoint controllers"]
        CCM["cloud-controller-manager\nCloud LB / Route\nprogramming"]
    end

    subgraph DP["Data Plane (worker nodes)"]
        KL["kubelet\nPod lifecycle\nCNI / CSI invocation"]
        KP["kube-proxy\niptables / IPVS\nService VIP → Pod IP"]
        CNI["CNI Plugin\nveth / bridge / eBPF\nIPAM"]
        POD1["Pod A\nnetns + veth0\n10.0.0.5"]
        POD2["Pod B\nnetns + veth1\n10.0.0.6"]
    end

    API <-->|watches / updates| ETCD
    SCHED -->|bind pod to node| API
    CM -->|reconcile desired state| API
    CCM -->|cloud API calls| API
    KL -->|node heartbeat + pod status| API
    KL -->|exec add/del| CNI
    KP -->|watch Services + Endpoints| API
    CNI --> POD1
    CNI --> POD2

    style CP fill:#1a2a4a,color:#fff
    style DP fill:#1a3a2a,color:#fff
    style API fill:#1565C0,color:#fff
    style ETCD fill:#0d47a1,color:#fff
    style SCHED fill:#1976D2,color:#fff
    style CM fill:#1976D2,color:#fff
    style CCM fill:#1976D2,color:#fff
    style KL fill:#2E7D32,color:#fff
    style KP fill:#2E7D32,color:#fff
    style CNI fill:#388E3C,color:#fff
    style POD1 fill:#43A047,color:#fff
    style POD2 fill:#43A047,color:#fff
```

> **Key insight:** The control plane never touches packet forwarding. kubelet and kube-proxy on each worker node do all the dataplane work, driven by watch streams from the API server.

---

## 2. Pod Networking — Single Node

Every pod gets its own Linux network namespace connected to the node via a **veth pair**. The node side of each veth attaches to a bridge (or eBPF program), which forwards between pods and to the node's physical NIC.

```mermaid
flowchart LR
    subgraph NODE["Worker Node (Linux kernel)"]
        subgraph NS1["Pod A netns"]
            ETH0A["eth0\n10.0.0.5/24"]
        end
        subgraph NS2["Pod B netns"]
            ETH0B["eth0\n10.0.0.6/24"]
        end
        subgraph NS3["Pod C netns"]
            ETH0C["eth0\n10.0.0.7/24"]
        end
        VETHA["veth-a (host end)"]
        VETHB["veth-b (host end)"]
        VETHC["veth-c (host end)"]
        BR["cni0 bridge\n10.0.0.1/24"]
        ETH1["eth1 (physical NIC)\n192.168.1.10"]
    end

    ETH0A <-->|veth pair| VETHA
    ETH0B <-->|veth pair| VETHB
    ETH0C <-->|veth pair| VETHC
    VETHA --> BR
    VETHB --> BR
    VETHC --> BR
    BR --> ETH1

    style NS1 fill:#0d47a1,color:#fff
    style NS2 fill:#0d47a1,color:#fff
    style NS3 fill:#0d47a1,color:#fff
    style BR fill:#2E7D32,color:#fff
    style ETH1 fill:#4a4a4a,color:#fff
```

> **What CNI does:** At pod start, kubelet calls the CNI plugin binary with `ADD`. CNI creates the veth pair, moves one end into the pod's netns, assigns an IP via IPAM, and programs a route on the bridge. At pod deletion it calls `DEL` to clean up.

---

## 3. Pod-to-Pod Traffic — Across Nodes

When Pod A on Node 1 sends a packet to Pod B on Node 2, the packet must cross the underlay network. CNI plugins solve this in two fundamentally different ways: **overlay** (encapsulate) or **underlay routing** (BGP).

```mermaid
flowchart LR
    subgraph N1["Node 1  192.168.1.10"]
        PA["Pod A\n10.0.0.5"]
        BR1["bridge / eBPF"]
        VTEP1["VTEP\n(VXLAN encap)\nor BGP route"]
        NIC1["eth1"]
    end

    subgraph UNDERLAY["Physical Network / VPC"]
        SW["L3 Switch / Router\nor AWS VPC route table"]
    end

    subgraph N2["Node 2  192.168.1.11"]
        NIC2["eth1"]
        VTEP2["VTEP\n(VXLAN decap)\nor BGP route"]
        BR2["bridge / eBPF"]
        PB["Pod B\n10.1.0.5"]
    end

    PA --> BR1
    BR1 --> VTEP1
    VTEP1 -->|"OVERLAY: UDP/4789 outer: 192.168.1.10→192.168.1.11\nUNDERLAY: BGP route 10.1.0.0/24 via 192.168.1.11"| SW
    SW --> NIC2
    NIC2 --> VTEP2
    VTEP2 --> BR2
    BR2 --> PB

    style N1 fill:#1a2a4a,color:#fff
    style N2 fill:#1a2a4a,color:#fff
    style UNDERLAY fill:#3a2a1a,color:#fff
    style PA fill:#1565C0,color:#fff
    style PB fill:#1565C0,color:#fff
    style SW fill:#8B4513,color:#fff
```

| Approach | CNI Example | Encapsulation | Requires |
|----------|------------|---------------|----------|
| Overlay (VXLAN) | Flannel, Calico VXLAN mode | UDP 4789 wrapper | No underlay changes |
| Underlay (BGP) | Calico BGP, Cilium native | None — real IPs | Router peering |
| Cloud native | AWS VPC CNI, GKE | None — VPC routes | Cloud IAM |

---

## 4. CNI Plugin Comparison

The three dominant CNI families use fundamentally different dataplanes.

```mermaid
flowchart TD
    subgraph CALICO["Calico CNI"]
        C1["Felix agent\n(policy enforcement)"]
        C2["BIRD daemon\n(BGP peering)"]
        C3["iptables / eBPF\n(dataplane choice)"]
        C4["IPAM: pod CIDR\nper node"]
        C1 --> C3
        C2 --> C3
    end

    subgraph CILIUM["Cilium CNI"]
        CL1["Cilium agent"]
        CL2["eBPF programs\nloaded into kernel"]
        CL3["Hubble\n(flow observability)"]
        CL4["IPAM: CRD or\nAWS/Azure mode"]
        CL1 --> CL2
        CL2 --> CL3
    end

    subgraph VPC["AWS VPC CNI"]
        V1["ipamd daemon\n(IP pre-allocation)"]
        V2["ENI secondary IPs\nassigned to pods"]
        V3["VPC Security Groups\nper pod (optional)"]
        V1 --> V2
        V2 --> V3
    end

    style CALICO fill:#1a3a2a,color:#fff
    style CILIUM fill:#1a2a4a,color:#fff
    style VPC fill:#3a2a1a,color:#fff
    style C1 fill:#2E7D32,color:#fff
    style C2 fill:#2E7D32,color:#fff
    style C3 fill:#388E3C,color:#fff
    style CL1 fill:#1565C0,color:#fff
    style CL2 fill:#1565C0,color:#fff
    style CL3 fill:#1976D2,color:#fff
    style V1 fill:#E65100,color:#fff
    style V2 fill:#E65100,color:#fff
    style V3 fill:#BF360C,color:#fff
```

| Feature | Calico | Cilium | AWS VPC CNI |
|---------|--------|--------|------------|
| Dataplane | iptables or eBPF | eBPF only | VPC routes |
| BGP peering | Yes (BIRD) | Optional | No |
| NetworkPolicy | Yes | Yes + extended | Yes (via SG) |
| Observability | Limited | Hubble (rich) | VPC Flow Logs |
| Pod density limit | None | None | ENI slots |

---

## 5. Kubernetes Service Types — Traffic Paths

A Service is a stable virtual IP (ClusterIP) backed by an Endpoints list. kube-proxy (or eBPF) translates the VIP to a real pod IP at the kernel level using DNAT.

```mermaid
flowchart LR
    subgraph EXTERNAL["External Traffic"]
        INET["Internet\nclient"]
        INTCLIENT["Internal\nclient (VM)"]
    end

    subgraph CLUSTER["Kubernetes Cluster"]
        subgraph SVC["Service Types"]
            CIP["ClusterIP\n10.96.x.x\ncluster-internal only"]
            NP["NodePort\n:30000-32767\nreachable via any node IP"]
            LB["LoadBalancer\nCloud LB IP\npublic or internal"]
            EXT["ExternalName\nCNAME alias\nno proxy"]
        end

        POD1["Pod replica 1\n10.0.0.5:8080"]
        POD2["Pod replica 2\n10.0.1.5:8080"]
        POD3["Pod replica 3\n10.0.2.5:8080"]

        CIP -->|"DNAT (iptables/eBPF)\nrandom / session-affinity"| POD1
        CIP --> POD2
        CIP --> POD3
        NP --> CIP
        LB --> NP
    end

    INET -->|"TCP :443"| LB
    INTCLIENT -->|"TCP :30080"| NP
    INTCLIENT -->|"TCP ClusterIP"| CIP

    style EXTERNAL fill:#3a2a1a,color:#fff
    style CLUSTER fill:#1a2a1a,color:#fff
    style CIP fill:#1565C0,color:#fff
    style NP fill:#2E7D32,color:#fff
    style LB fill:#E65100,color:#fff
    style EXT fill:#6a1a8a,color:#fff
    style POD1 fill:#0d47a1,color:#fff
    style POD2 fill:#0d47a1,color:#fff
    style POD3 fill:#0d47a1,color:#fff
```

> **How kube-proxy works:** It watches the API server for Service/Endpoints changes and writes iptables DNAT rules (or IPVS entries, or loads eBPF programs in Cilium kube-proxy replacement mode). The kernel intercepts packets destined for the ClusterIP and rewrites the destination before routing.

---

## 6. State of the Art — 2026 Kubernetes Dataplane

Modern production clusters are moving from iptables to eBPF. Here is the full picture of where the industry stands.

```mermaid
flowchart TD
    subgraph LEGACY["Legacy Dataplane (pre-2022)"]
        L1["kube-proxy writes iptables rules\nO(n) lookup — slow at 10k+ Services"]
        L2["CNI uses Linux bridge + iptables\nconntrack for every flow"]
        L3["No per-flow observability\nonly node-level metrics"]
        L1 --> L2 --> L3
    end

    subgraph MODERN["Modern Dataplane (2023+)"]
        M1["Cilium kube-proxy replacement\neBPF O(1) hash map — scales to 100k Services"]
        M2["XDP for DDoS / LB offload\npackets never enter kernel stack"]
        M3["Hubble / Tetragon\nper-flow L3-L7 visibility + security audit"]
        M4["WireGuard node-to-node encryption\nkernelspace — zero user-space overhead"]
        M1 --> M2
        M1 --> M3
        M1 --> M4
    end

    subgraph CLOUD["Cloud-Native Additions"]
        CL1["Gateway API replaces Ingress\nexpressive routing, multi-tenant"]
        CL2["SPIFFE/SPIRE + mTLS\nworkload identity without IP trust"]
        CL3["IPAM from cloud IPAM\n(AWS prefix delegation, Azure CNI overlay)"]
    end

    LEGACY -->|"Migration path: deploy Cilium\nin migration mode alongside kube-proxy"| MODERN
    MODERN --- CLOUD

    style LEGACY fill:#4a1a1a,color:#fff
    style MODERN fill:#1a3a1a,color:#fff
    style CLOUD fill:#1a1a4a,color:#fff
    style L1 fill:#C62828,color:#fff
    style L2 fill:#C62828,color:#fff
    style L3 fill:#C62828,color:#fff
    style M1 fill:#2E7D32,color:#fff
    style M2 fill:#2E7D32,color:#fff
    style M3 fill:#388E3C,color:#fff
    style M4 fill:#388E3C,color:#fff
    style CL1 fill:#1565C0,color:#fff
    style CL2 fill:#1565C0,color:#fff
    style CL3 fill:#1565C0,color:#fff
```

| Era | kube-proxy | CNI dataplane | Observability | Encryption |
|-----|-----------|---------------|---------------|------------|
| 2018–2021 | iptables | bridge + conntrack | node metrics only | manual mTLS |
| 2022–2023 | IPVS option | Calico eBPF (beta) | Hubble (alpha) | WireGuard |
| 2024–2026 | Cilium replacement | eBPF XDP | Hubble + Tetragon | WireGuard default |

---

## What Comes Next

Each diagram above is covered in depth in later lessons:

| Diagram | Deep-dive lesson |
|---------|-----------------|
| Control / data plane split | [Lesson 01 — Linux Networking Fundamentals](01-linux-networking-fundamentals.md) |
| Pod networking on a node | [Lesson 04 — Network Namespaces Deep Dive](04-network-namespaces-deep-dive.md) |
| Cross-node traffic | [Lesson 05 — VXLAN and Overlay Networks](05-vxlan-and-overlay-networks.md) |
| CNI comparison | [Lesson 11 — Calico CNI](11-calico-cni-deep-dive.md) · [Lesson 12 — Cilium CNI](12-cilium-cni-ebpf.md) |
| Service types | [Lesson 13 — Kubernetes Services and kube-proxy](13-kubernetes-services-kube-proxy.md) |
| eBPF dataplane | [Lesson 10 — eBPF and XDP](10-ebpf-xdp.md) · [Lesson 12 — Cilium CNI](12-cilium-cni-ebpf.md) |
