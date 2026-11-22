# Lab Validation Scripts

Each script verifies that you successfully completed the hands-on exercise for a given lesson.
Run the script after finishing the lab to confirm your work.

## Scripts

| Script | Lesson | Title | Where to Run |
|---|---|---|---|
| `validate-setup.sh` | Pre-course | Environment Setup | Mac terminal |
| `validate-01.sh` | Lesson 01 | Linux Networking Fundamentals | `minikube ssh` |
| `validate-03.sh` | Lesson 03 | iptables and Connection Tracking | `minikube ssh` |
| `validate-09.sh` | Lesson 09 | CNI Specification and Plugins | `minikube ssh` (+ kubectl note) |
| `validate-13.sh` | Lesson 13 | Kubernetes Services | Mac terminal (kubectl) |
| `validate-14.sh` | Lesson 14 | CoreDNS and Service Discovery | Mac terminal (kubectl) |
| `validate-16.sh` | Lesson 16 | Kubernetes NetworkPolicy | Mac terminal (kubectl) |

---

## Quick start

### Mac terminal scripts

```bash
bash labs/validate-setup.sh   # run before starting the course
bash labs/validate-13.sh
bash labs/validate-14.sh
bash labs/validate-16.sh
```

### minikube ssh scripts

Copy the script into the VM, or pipe it in:

```bash
# Option A — pipe from the Mac
cat labs/validate-01.sh | minikube ssh -- bash

# Option B — copy first, then run inside the VM
minikube cp labs/validate-01.sh /home/docker/validate-01.sh
minikube ssh
  bash /home/docker/validate-01.sh
```

---

## What each script checks

### validate-setup.sh — Pre-course environment

- minikube is running (`minikube status`)
- kubectl is installed and can reach the cluster (`kubectl cluster-info`)
- `minikube ssh` is functional (returns a kernel version)
- `bpftool` is available inside the VM (needed for eBPF lessons — warns if missing)
- Required Mac-side tools: `kubectl`, `helm`
- Optional tools: `curl`, `jq`, `python3`, `docker`

### validate-01.sh — Linux Networking Fundamentals

- A veth pair is present (`ip link | grep veth`)
- A Linux bridge interface exists (`ip link show type bridge`)
- IP forwarding is enabled (`sysctl net.ipv4.ip_forward == 1`)

### validate-03.sh — iptables and Connection Tracking

- `KUBE-SERVICES` chain exists in the `nat` table
- `conntrack` tool is available and the table is accessible
- `iptables-save` output contains KUBE rules

### validate-09.sh — CNI Specification and Plugins

- `/opt/cni/bin/` exists and contains at least one binary
- `/etc/cni/net.d/` exists and contains at least one config file
- Note: the "pod is Running" check must be done from the Mac (`kubectl get pods -A`)

### validate-13.sh — Kubernetes Services

- At least one ClusterIP service exists
- `KUBE-SERVICES` iptables chain exists (checked via the kube-proxy pod)
- At least one EndpointSlice exists (`kubectl get endpointslices -A`)

### validate-14.sh — CoreDNS and Service Discovery

- CoreDNS pods are in Running state
- `kube-dns` service exists in `kube-system`
- DNS resolution works: `nslookup kubernetes` succeeds inside a temporary pod
- Pod `resolv.conf` contains `ndots:5`

### validate-16.sh — NetworkPolicy

- At least one NetworkPolicy exists across all namespaces
- A default-deny ingress policy exists (empty `podSelector` with no ingress rules)

---

## Exit codes

All scripts exit **0** if every check passes, **1** if any check fails.
