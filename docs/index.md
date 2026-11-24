# Platform Network Engineering

> Three books in one — Kubernetes Networking · Cloud Foundry Networking · Migration Guide

---

## Books

<div class="grid cards" markdown>

- :fontawesome-brands-kubernetes: **Kubernetes Networking**  
  34 lessons from Linux foundations through CNI, service meshes, OpenShift, AWS, GitOps, and AI GPU cluster networking.  
  [Start Track A →](lessons/01-linux-networking-fundamentals.md)

- :fontawesome-solid-cloud: **Cloud Foundry Networking**  
  20 lessons covering Diego, Silk CNI, GoRouter, CF-to-CF mTLS, BTP Private Link, and hybrid connectivity.  
  [Start CF Book →](cf/cf-00-overview.md)

- :fontawesome-solid-arrows-left-right: **K8s ↔ CF Migration Guide**  
  Side-by-side networking concepts, migration patterns, and decision frameworks for teams moving workloads.  
  [Open Migration Guide →](migration/mig-00-guide.md)

- :fontawesome-solid-table-list: **Cheat Sheets**  
  Quick-reference cards for kubectl, calicoctl, cilium, cf CLI networking commands, and iptables.  
  [Browse Cheat Sheets →](cheatsheets/cs-00-index.md)

</div>

---

## Kubernetes Networking — 9 Tracks

<div class="grid cards" markdown>

- :fontawesome-solid-network-wired: **[Track A — Linux Foundations](lessons/01-linux-networking-fundamentals.md)**  
  veth pairs · bridges · iptables · namespaces · VXLAN · BGP · bare metal

- :fontawesome-solid-plug: **[Track B — CNI Plugins & eBPF](lessons/09-cni-specification.md)**  
  CNI spec · eBPF/XDP · Calico · Cilium

- :fontawesome-brands-kubernetes: **[Track C — Kubernetes Networking](lessons/13-kubernetes-services-kube-proxy.md)**  
  Services · CoreDNS · IPv6 · NetworkPolicy

- :fontawesome-solid-route: **[Track D — Ingress & Load Balancing](lessons/17-ingress-controllers.md)**  
  Ingress · Gateway API · MetalLB · Cloud LBs

- :fontawesome-solid-layer-group: **[Track E — Advanced Topics](lessons/21-service-mesh-istio.md)**  
  Istio · Multi-cluster · Security · Observability

- :fontawesome-brands-redhat: **[Track F — OpenShift](lessons/25-openshift-networking-overview.md)**  
  OVN-Kubernetes · Routes · EgressIP

- :fontawesome-brands-aws: **[Track G — AWS](lessons/29-aws-eks-networking.md)**  
  EKS · VPC design · ALB/NLB controller · Hybrid

- :fontawesome-solid-code-branch: **[Track H — GitOps](lessons/33-argocd-gitops.md)**  
  ArgoCD · sync waves · multi-cluster delivery

- :fontawesome-solid-microchip: **[Track I — AI Platform](lessons/34-ai-platform-networking.md)**  
  RDMA · SR-IOV · Multus · RoCE · EFA · GPU Operator

</div>

---

## Practice Environment

Every lesson uses two terminals:

```bash
# Terminal 1 — Linux node (kernel commands)
minikube ssh

# Terminal 2 — Mac / local machine (kubectl)
kubectl get pods -A
```

Linux-only commands (`ip netns`, `iptables`, `bpftool`) run inside `minikube ssh`.  
Cluster commands (`kubectl`, `calicoctl`, `cilium`) run from your local terminal.

---

## Learning Path

```mermaid
flowchart LR
    A["Track A\nLinux Foundations\n01–07"] --> B
    A --> C
    B["Track B\nCNI & eBPF\n08–12"] --> C
    C["Track C\nK8s Networking\n13–16"] --> D
    C --> E
    D["Track D\nIngress & LB\n17–20"] --> E
    E["Track E\nAdvanced\n21–24"] --> F
    E --> G
    F["Track F\nOpenShift\n25–28"]
    G["Track G\nAWS\n29–32"] --> H
    H["Track H\nGitOps\n33"] --> I
    I["Track I\nAI Platform\n34"]
```

---

## Course Stats

| Metric | Value |
|--------|-------|
| Lessons | 34 (K8s) + 20 (CF) |
| Tracks | 9 (K8s) + 5 (CF) |
| Mermaid diagrams | 90+ |
| Troubleshooting entries | 230+ |
| Practice commands | 400+ |
| Free resources mapped | 25+ |

---

## Downloads

| Book | EPUB | PDF |
|------|------|-----|
| Kubernetes Networking (34 lessons) | [EPUB 4.7 MB](https://github.com/MykolaLebid/Kubernetes_networking_engineering/raw/main/kubernetes-network-engineering.epub) | [PDF 13 MB](https://github.com/MykolaLebid/Kubernetes_networking_engineering/raw/main/kubernetes-network-engineering.pdf) |
| Cloud Foundry Networking (20 lessons + migration) | [EPUB 3.1 MB](https://github.com/MykolaLebid/Kubernetes_networking_engineering/raw/main/cf-networking.epub) | — |

All EPUB files reflow on reMarkable and e-readers.

---

## Free Resources

See [RESOURCES.md](RESOURCES.md) for a curated list of free interactive labs, playgrounds, and courses mapped to every lesson.
