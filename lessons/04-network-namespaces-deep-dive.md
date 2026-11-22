# Lesson 04 — Network Namespaces Deep Dive

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 01 — Linux Networking Fundamentals](01-linux-networking-fundamentals.md)  
> **Duration:** ~2 hours

---

## Practice Setup

```bash
# Run all commands inside minikube
minikube ssh

# See real pod namespaces
ip netns list

# Inspect a pod's namespace (find the pause PID first)
sudo crictl ps | head -5
```

---

## Why This Matters

Network namespaces are the kernel primitive that gives each Kubernetes pod its own isolated network identity. Understanding their lifecycle — creation, wiring, inspection, and teardown — lets you reason about pod networking at the most fundamental level.

---

## 1. What a Network Namespace Contains

A network namespace is a **complete, isolated copy** of the network stack:

| Resource | Isolated per namespace |
|----------|----------------------|
| Network interfaces | Yes (lo, eth0, etc.) |
| IP addresses | Yes |
| Routing tables | Yes |
| iptables/nftables rules | Yes |
| Conntrack table | Yes |
| Sockets | Yes (can't be shared across namespaces) |
| BPF programs attached to interfaces | Yes |

What is **not** isolated: the physical hardware, kernel sysctl `net.*` globals (partially), and network namespaces themselves (they are managed from the host).

---

## 2. Creating and Managing Network Namespaces

```bash
# Create a named namespace (creates /var/run/netns/<name>)
ip netns add red
ip netns add blue

# List all named namespaces
ip netns list
ip netns list -details     # show if namespace file is a bind mount

# Execute a command in a namespace
ip netns exec red ip link list
ip netns exec red bash     # interactive shell in the namespace

# Delete
ip netns del red

# Show which namespace a process is in
ls -la /proc/<pid>/ns/net
# Namespaces of all processes:
# ls -la /proc/*/ns/net | sort -k11
```

---

## 3. How Kubernetes Uses Network Namespaces

The kubelet/container runtime creates a pod namespace using the **pause container**:

```bash
# Find the pause container for a pod
crictl ps | grep pause
# or:
docker ps | grep pause

# Get the pause container's PID
PAUSE_PID=$(crictl inspect <container-id> | jq '.info.pid')

# Access its network namespace
nsenter --target $PAUSE_PID --net -- ip addr
nsenter --target $PAUSE_PID --net -- ip route
nsenter --target $PAUSE_PID --net -- ss -tlnp

# Alternative: find the namespace path from the pod UID
ls /var/run/netns/   # on containerd-based nodes, the path may differ
# containerd: /proc/<pause_pid>/ns/net (accessed via nsenter or /proc)
```

All containers in the same pod share this namespace, which is why they can communicate via `localhost` and share port space.

---

## 4. Inspecting Pod Network Namespaces from the Host

```bash
# Method 1: nsenter (most reliable)
POD_NS=$(kubectl get pod <pod-name> -o jsonpath='{.metadata.uid}')
PAUSE_PID=$(crictl inspect $(crictl ps | grep $POD_NS | head -1 | awk '{print $1}') | jq -r '.info.pid')

nsenter -t $PAUSE_PID -n ip addr
nsenter -t $PAUSE_PID -n ip route
nsenter -t $PAUSE_PID -n ss -s

# Method 2: netshoot (run a debug pod in the same namespace)
kubectl debug -it <pod-name> --image=nicolaka/netshoot --target=<container-name>

# Method 3: kubectl exec with network tools
kubectl exec -it <pod-name> -- sh
# Then: ip addr, ip route, ss, nslookup, curl
```

---

## 5. Network Namespace Lifecycle with CNI

When a pod is scheduled, this sequence occurs:

```
kubelet → CRI (containerd/crio)
  1. CRI creates the pod sandbox (pause container)
     └── Calls: clone(CLONE_NEWNET) → new network namespace created
     └── Namespace file: /var/run/netns/cni-<uuid>  (bind-mounted for CNI)

  2. CRI calls CNI plugin: ADD command
     └── CNI reads namespace path from args
     └── CNI creates veth pair
     └── CNI moves one veth end into the namespace
     └── CNI assigns IP address
     └── CNI sets up routes (inside namespace and on host)
     └── CNI may install iptables/eBPF rules

  3. App containers join the same namespace (--network=container:pause)

  4. Pod is Running

When pod is deleted:
  5. CRI calls CNI plugin: DEL command
     └── CNI removes IP from IPAM pool
     └── CNI removes host-side veth (destroying the pair)
     └── CNI removes routes
  6. CRI destroys the namespace
     └── Namespace file unlinked
     └── Last reference drops → kernel frees the namespace
```

---

## 6. Namespace Sharing Edge Cases

### hostNetwork pods
Some system pods (kube-proxy, CNI agents) run in the **host network namespace**:

```yaml
spec:
  hostNetwork: true
```

```bash
# These pods appear in host routing/iptables
kubectl get pod -n kube-system -o wide | grep -E "kube-proxy|calico-node"
# Their IPs are node IPs, not pod CIDR IPs
```

Risks: a compromised `hostNetwork` pod can see and modify all host network state.

### Shared network between pods (non-standard)
Pods can share a namespace using `shareProcessNamespace` + init container tricks, but the standard model is one namespace per pod.

---

## 7. Namespace File Descriptors and Pinning

A namespace exists as long as either:
- A process is running inside it, **or**
- A file descriptor referencing it is open (bind-mount counts)

```bash
# Bind-mount a namespace so it persists without a process
touch /tmp/netns-persist
mount --bind /proc/$$/ns/net /tmp/netns-persist

# Open a namespace from its bind-mount path
ip netns exec $(readlink /tmp/netns-persist) ip addr

# This is exactly how CNI keeps the pod namespace alive
# when the pause container hasn't started yet
ls -la /var/run/netns/
```

---

## 8. Debugging Namespace Leaks

After a node has been running a long time, stale namespace files can accumulate if cleanup fails.

```bash
# Count active namespaces
ls /var/run/netns/ | wc -l

# Check for orphaned namespaces (no pause container for them)
for ns in /var/run/netns/cni-*; do
  ns_id=$(basename $ns)
  pid=$(lsns -t net -o PID,NETNSID | grep $ns_id | awk '{print $1}')
  if [ -z "$pid" ]; then
    echo "ORPHAN: $ns"
  fi
done

# View all network namespaces the kernel knows about
lsns -t net

# Identify which pods use each namespace
crictl pods --no-trunc -o json | jq -r '.items[] | .metadata.name + " " + .status.linux.namespaces[] | select(.type=="network") | .path'
```

---

## 9. Hands-On Lab: Full Pod Namespace Simulation

Reproduce the entire pod network namespace lifecycle manually.

```bash
# Step 1: Create the namespace (simulating CRI)
ip netns add cni-pod-sim

# Step 2: Create veth pair (simulating CNI ADD)
ip link add eth0-host type veth peer name eth0
ip link set eth0 netns cni-pod-sim

# Step 3: Set up bridge on host
ip link add cni0 type bridge
ip link set cni0 up
ip addr add 10.244.0.1/24 dev cni0
ip link set eth0-host master cni0
ip link set eth0-host up

# Step 4: Configure pod namespace
ip netns exec cni-pod-sim ip link set lo up
ip netns exec cni-pod-sim ip link set eth0 up
ip netns exec cni-pod-sim ip addr add 10.244.0.100/24 dev eth0
ip netns exec cni-pod-sim ip route add default via 10.244.0.1

# Step 5: Verify
ip netns exec cni-pod-sim ip addr
ip netns exec cni-pod-sim ip route
ip netns exec cni-pod-sim ping -c3 10.244.0.1

# Step 6: Simulate CNI DEL (pod deletion)
ip link del eth0-host     # destroys veth pair; eth0 inside ns also gone
ip link del cni0
ip netns del cni-pod-sim
```

---

## 10. Summary

| Concept | Key Detail |
|---------|-----------|
| Namespace creation | `clone(CLONE_NEWNET)` or `ip netns add` |
| Persistence mechanism | Bind-mount at `/var/run/netns/<name>` |
| Pod namespace holder | pause (infra) container |
| Inspect from host | `nsenter -t <pause_pid> -n <cmd>` |
| CNI role | Wires veth pair into namespace, assigns IP/routes |
| hostNetwork pods | Share host namespace — elevated privilege |
| Namespace leak | Orphaned `/var/run/netns/cni-*` files after failed cleanup |

---

**Next:** [Lesson 05 — VXLAN and Overlay Networks](05-vxlan-and-overlay-networks.md)
