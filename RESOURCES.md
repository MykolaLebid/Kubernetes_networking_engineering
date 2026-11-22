# Free Online Learning Resources

All resources listed here are **free** (or have a meaningful free tier). Each is mapped to the lessons where it is most useful.

---

## Quick Reference — Best Free Platform per Topic

| You want to learn… | Best free resource |
|--------------------|-------------------|
| Linux networking primitives (veth, namespaces, bridges) | [iximiuz: Container Networking from Scratch](https://labs.iximiuz.com/tutorials/container-networking-from-scratch) |
| Any kubectl / Kubernetes command practice | [Killercoda Playground](https://killercoda.com/) |
| eBPF — write and load real programs | [ebpf.io Interactive Lab](https://ebpf.io/labs/) |
| XDP programs in C | [xdp-project/xdp-tutorial](https://github.com/xdp-project/xdp-tutorial) |
| Cilium + Hubble + Gateway API | [Isovalent Interactive Labs](https://isovalent.com/labs/) |
| NetworkPolicy YAML builder | [NetworkPolicy Editor](https://editor.networkpolicy.io/) |
| Istio mTLS + traffic management | [Istio Getting Started](https://istio.io/latest/docs/setup/getting-started/) |
| Istio structured course with labs | [Tetrate Academy](https://academy.tetrate.io/courses/istio-fundamentals) |
| OpenShift Routes + EgressIP | [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) |
| AWS EKS networking | [EKS Workshop](https://www.eksworkshop.com/) |
| AWS simulated labs (no AWS cost) | [AWS Skill Builder](https://skillbuilder.aws/) |
| ArgoCD GitOps | [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/) |
| GPU Operator on Kubernetes | [NVIDIA GPU Operator Docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html) |

---

## Platform Descriptions

### [Killercoda](https://killercoda.com/) — Free
Browser-based Linux and Kubernetes environments. Spins up in 30 seconds — no local install. Use for any lesson that needs a real Linux node or Kubernetes cluster. Search "Kubernetes Networking" or "Linux" in the explore page for community scenarios.

**Best for:** Lessons 01–24 (any `minikube ssh` or `kubectl` commands)

---

### [iximiuz Labs](https://labs.iximiuz.com/) — Free
Interactive container and Kubernetes labs by Ivan Velichko (former Google SRE). Automated verification tells you when you've solved a challenge correctly.

| Resource | Lessons |
|----------|---------|
| [Container Networking from Scratch](https://labs.iximiuz.com/tutorials/container-networking-from-scratch) | 01, 02, 04, 05 |
| [eBPF Beginner Challenge](https://labs.iximiuz.com/challenges/ebpf-beginner-challenge-89ffd924) | 10 |
| [Networking Challenges](https://labs.iximiuz.com/challenges) | 24 |

---

### [Isovalent Interactive Labs](https://isovalent.com/labs/) — Free
Official Cilium/eBPF labs. Browser-based, no account needed for most. Each lab runs in a real Kubernetes cluster with Cilium installed.

| Lab | Lessons |
|----|---------|
| [Foundations: Kubernetes Networking and Cilium](https://isovalent.com/labs/getting-started-with-kubernetes-networking-and-cilium/) | 09, 12, 13 |
| [Getting Started with Cilium](https://isovalent.com/labs/getting-started-with-cilium/) | 12 |
| [Build an eBPF Monitoring Tool](https://isovalent.com/labs/ebpf-monitoring-tool-for-kubernetes/) | 10 |
| [Cilium: Host Firewall](https://isovalent.com/labs/cilium-host-firewall/) | 16 |
| [Gateway API + cert-manager](https://isovalent.com/labs/cilium-gateway-api-cert-manager/) | 18 |
| [Advanced Gateway API Use Cases](https://isovalent.com/labs/advanced-gateway-api-use-cases/) | 18 |
| [Gateway API: External Authentication](https://isovalent.com/labs/cilium-gateway-api-external-authentication/) | 18 |
| [Cilium Cluster Mesh](https://isovalent.com/labs/cilium-cluster-mesh/) | 22 |
| [Zero Trust Visibility](https://isovalent.com/labs/zero-trust-visibility/) | 23, 24 |
| [TLS Visibility](https://isovalent.com/labs/tls-visibility/) | 21 |

---

### [ebpf.io Interactive Lab](https://ebpf.io/labs/) — Free
Write and load a real eBPF program in your browser. Based on the `opensnoop` example. No kernel setup, no install.

**Best for:** Lesson 10 (eBPF and XDP)

---

### [xdp-project/xdp-tutorial](https://github.com/xdp-project/xdp-tutorial) — Free
Step-by-step C labs writing XDP programs with an automated `testenv` setup script. Covers every XDP return code and TC hook.

**Best for:** Lesson 10 (eBPF and XDP)

---

### [NetworkPolicy Editor](https://editor.networkpolicy.io/) — Free browser tool
Drag-and-drop visual NetworkPolicy builder. Build policies graphically, see the selector logic, export YAML, test in-browser. No account needed.

**Best for:** Lessons 16, 23

---

### [Kubernetes Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes) — Free
20+ ready-to-use NetworkPolicy examples: default-deny, namespace isolation, CIDR-based, metadata API block. Apply directly with `kubectl apply -f`.

**Best for:** Lessons 16, 23

---

### [Istio — Get Started](https://istio.io/latest/docs/setup/getting-started/) — Free
Official Istio quickstart on minikube. Deploys the Bookinfo app, enables mTLS, configures VirtualService traffic splitting. Covers the full lesson 21 flow.

**Best for:** Lesson 21 (Service Mesh / Istio)

---

### [Tetrate Academy — Istio Fundamentals](https://academy.tetrate.io/courses/istio-fundamentals) — Free (account required)
Free Istio course from Tetrate (major Istio contributor) with browser-based labs. Covers PeerAuthentication, AuthorizationPolicy, DestinationRule, and Envoy filters. Free certificate on completion.

**Best for:** Lesson 21 (Service Mesh / Istio)

---

### [Submariner Quickstart](https://submariner.io/getting-started/quickstart/) — Free
Connect two local kind clusters with Submariner. Free substitute for practicing cross-cluster pod connectivity without cloud infrastructure.

**Best for:** Lesson 22 (Multi-Cluster Networking)

---

### [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) — Free (30 days)
Real OpenShift cluster for 30 days. The only free way to run `oc get egressip`, HAProxy routes, `ovs-vsctl show`, and OVN commands.

**Best for:** Lessons 25–28 (OpenShift track)

**Setup:**
```bash
# After signing up, download oc CLI and login
oc login --token=<your-token> --server=<sandbox-url>
oc get network.operator cluster -o yaml
```

---

### [Red Hat Interactive Learning Portal](https://www.redhat.com/en/interactive-labs/openshift) — Free (Red Hat account)
Guided browser-based OpenShift labs. Shorter than the Sandbox but no 30-day limit.

**Best for:** Lessons 25–28 (OpenShift track)

---

### [AWS EKS Workshop](https://www.eksworkshop.com/) — Free workshop (~$3 AWS cost)
Full hands-on EKS workshop covering VPC CNI, NLB/ALB, Security Groups for Pods, Transit Gateway, and more. Run the networking modules only (~2 hours, ~$3 in AWS costs if you clean up).

```bash
# Run cleanup after each session to avoid charges
eksctl delete cluster --name eksworkshop-eksctl
```

**Best for:** Lessons 29–32 (AWS track)

---

### [AWS Skill Builder](https://skillbuilder.aws/) — Free (AWS account required)
Official AWS simulated labs with no live infrastructure cost. Slower than a real cluster but zero AWS spend.

**Best for:** Lessons 29–32 (AWS track)

---

### [Amazon EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/networking/index/) — Free
Deep reference documentation for EKS networking: VPC CNI design, pod density, custom networking, load balancers. Use as a reference alongside the AWS lessons.

**Best for:** Lessons 29–31

---

### [ArgoCD — Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/) — Free
Official ArgoCD tutorial on minikube. Deploy ArgoCD, create an Application pointing to a Git repo, watch sync. 30-minute quickstart.

**Best for:** Lesson 33 (ArgoCD / GitOps)

---

### [Codefresh: GitOps Fundamentals](https://codefresh.io/learn/argo-cd/) — Free
Free ArgoCD course from Codefresh (Argo maintainers) with exercises covering ApplicationSets, sync waves, and multi-cluster deployments.

**Best for:** Lesson 33 (ArgoCD / GitOps)

---

### [ArgoCD Example Apps](https://github.com/argoproj/argocd-example-apps) — Free
Official sample applications for ArgoCD testing. Use as the Git repo target when practicing sync wave ordering for network-dependent resources.

**Best for:** Lesson 33 (ArgoCD / GitOps)

---

### [NVIDIA GPU Operator Docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html) — Free
Official quickstart for deploying the GPU Operator on Kubernetes. If you don't have GPU hardware, use the `--set driver.enabled=false` flag to test on CPU-only nodes.

**Best for:** Lesson 34 (AI Platform Networking)

---

### [Kubeflow — Getting Started](https://www.kubeflow.org/docs/started/getting-started/) — Free
Deploy distributed training with PyTorchJob on a local cluster. Observe how NCCL initializes collective communications between workers.

**Best for:** Lesson 34 (AI Platform Networking)

---

## Paid Options (notable value)

| Platform | Cost | Best for |
|----------|------|---------|
| [KodeKloud](https://www.kodekloud.com/learning-path/kubernetes) | ~$15/mo | 4h 31m Kubernetes Networking Deep Dive with auto-graded labs (lessons 09, 13, 14, 16, 17) |
| [killer.sh](https://killer.sh) | Included with CKA exam (~$395) | Timed exam simulation with real cluster — best pressure test for lessons 13, 16, 17 |
| [Linux Foundation CKA](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) | $395 (includes 2× killer.sh) | Official certification; demonstrates mastery of lessons 01–24 |

---

## Recommended Learning Sequence (free only)

```
Week 1 — Linux Foundations (Lessons 01–07)
  Primary: iximiuz Container Networking from Scratch
  Secondary: Killercoda Playground for all ip/iptables commands

Week 2 — CNI & eBPF (Lessons 08–12)
  Primary: Isovalent Labs (Foundations + Getting Started with Cilium)
  eBPF: ebpf.io lab + xdp-project tutorial

Week 3 — Kubernetes Networking (Lessons 13–16)
  Primary: Killercoda Playground
  Network Policy: NetworkPolicy Editor + kubernetes-network-policy-recipes

Week 4 — Ingress & Load Balancing (Lessons 17–20)
  Primary: Killercoda + Isovalent Gateway API labs
  AWS: AWS Skill Builder (simulated, free)

Week 5 — Advanced (Lessons 21–24)
  Istio: Official Getting Started + Tetrate Academy
  Multi-cluster: Submariner quickstart
  Security/Observability: Isovalent Zero Trust + Hubble labs

Week 6 — Platform Tracks
  OpenShift: Red Hat Developer Sandbox (sign up early — 30-day clock)
  AWS: EKS Workshop (pick one afternoon, clean up after)
  ArgoCD: Official getting-started + Codefresh course
```
