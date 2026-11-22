# Lesson 09 — CNI Specification and Plugin Architecture

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 04 — Network Namespaces](04-network-namespaces-deep-dive.md)  
> **Duration:** ~2 hours

---

## Practice Setup

```bash
# Terminal 1 — minikube node (inspect CNI config and binaries)
minikube ssh
ls /etc/cni/net.d/        # CNI config files
ls /opt/cni/bin/          # CNI plugin binaries

# Terminal 2 — kubectl (Mac)
kubectl get pods -A | grep calico   # the running CNI
```

---

## Why This Matters

CNI (Container Network Interface) is the plugin API that connects Kubernetes to any network implementation. The kubelet calls your CNI plugin when creating or deleting a pod. Understanding the spec lets you debug CNI failures, write custom plugins, and reason about why any CNI behaves the way it does.

---

## 1. What CNI Is

CNI is a **specification + set of libraries** defining how container runtimes configure network interfaces for containers. It is intentionally minimal:

- A CNI plugin is **an executable** (binary) placed in `/opt/cni/bin/`
- It receives configuration via **stdin** (JSON)
- It receives environment variables for context
- It outputs results on **stdout** (JSON)
- The runtime calls it on `ADD` (create pod), `DEL` (delete pod), and `CHECK` (verify) operations

---

## 2. CNI Environment Variables

```
CNI_COMMAND      ADD | DEL | CHECK | VERSION
CNI_CONTAINERID  Unique ID of the container (pod)
CNI_NETNS        Path to the network namespace: /var/run/netns/<id>
CNI_IFNAME       Interface name to create inside the container: eth0
CNI_ARGS         Extra K=V args (not widely used)
CNI_PATH         Colon-separated list of directories to search for CNI plugins
```

---

## 3. CNI Configuration File

Stored in `/etc/cni/net.d/`. The first file (alphabetically) is used.

```json
{
  "cniVersion": "1.0.0",
  "name": "my-network",
  "type": "bridge",
  "bridge": "cni0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "ranges": [
      [{"subnet": "10.244.0.0/24"}]
    ],
    "routes": [
      {"dst": "0.0.0.0/0"}
    ]
  }
}
```

For chained plugins (multiple plugins in sequence):
```json
{
  "cniVersion": "1.0.0",
  "name": "k8s-pod-network",
  "plugins": [
    {
      "type": "calico",
      "ipam": {"type": "calico-ipam"}
    },
    {
      "type": "bandwidth",
      "ingressRate": 10485760,
      "egressRate": 10485760
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true}
    }
  ]
}
```

---

## 4. CNI ADD Operation Flow

```
kubelet creates pod sandbox (pause container, network namespace)
  ↓
kubelet reads /etc/cni/net.d/10-calico.conflist
  ↓
kubelet sets CNI_COMMAND=ADD, CNI_NETNS=/var/run/netns/cni-xxx, CNI_IFNAME=eth0
  ↓
kubelet executes /opt/cni/bin/calico (passes config via stdin)
  ↓
calico binary:
  1. Calls IPAM plugin to get an IP address
  2. Creates a veth pair
  3. Moves one end (eth0) into CNI_NETNS
  4. Configures IP, routes inside the namespace
  5. Sets up host-side routing / iptables / eBPF
  6. Returns result JSON on stdout
  ↓
kubelet reads result, stores IP in pod status
```

---

## 5. CNI Result Format

```json
{
  "cniVersion": "1.0.0",
  "interfaces": [
    {
      "name": "eth0",
      "mac": "0a:58:0a:f4:00:06",
      "sandbox": "/var/run/netns/cni-abc123"
    }
  ],
  "ips": [
    {
      "interface": 0,
      "address": "10.244.0.6/24",
      "gateway": "10.244.0.1"
    }
  ],
  "routes": [
    {"dst": "0.0.0.0/0", "gw": "10.244.0.1"}
  ],
  "dns": {
    "nameservers": ["10.96.0.10"]
  }
}
```

---

## 6. IPAM Plugins

IPAM (IP Address Management) plugins handle IP allocation, called by the main CNI plugin.

### host-local
Allocates IPs from a range, stored in flat files on each node.
```bash
# IPAM state files
ls /var/lib/cni/networks/my-network/
# Files named after each allocated IP, containing container ID
```

### calico-ipam
Uses Calico's IPAM blocks (by default /26 per node) with central coordination via Kubernetes CRDs.
```bash
calicoctl ipam show --show-blocks
calicoctl ipam show --ip 10.244.0.6
```

### whereabouts
Cluster-wide IPAM with no per-node allocation boundaries (useful for Multus secondary networks).
```bash
kubectl get ippools.whereabouts.cni.cncf.io
kubectl get overlappingrangeipreservations.whereabouts.cni.cncf.io
```

### AWS VPC CNI IPAM
Allocates IPs from EC2 secondary ENI IPs; keeps a warm pool pre-provisioned.
```bash
kubectl get cm -n kube-system amazon-vpc-cni -o yaml | grep WARM_IP_TARGET
```

---

## 7. Multus — Multiple CNI Plugins Per Pod

Multus is a meta-CNI that calls multiple CNI plugins for a single pod, giving it multiple network interfaces.

```yaml
# Pod with extra SR-IOV NIC
apiVersion: v1
kind: Pod
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: '[
      {
        "name": "sriov-net",
        "interface": "net1"
      }
    ]'
spec:
  containers:
    - name: app
      image: app:latest
```

```bash
# Check Multus installation
kubectl get pods -n kube-system | grep multus
ls /etc/cni/net.d/00-multus.conf

# View network attachment definitions
kubectl get network-attachment-definitions -A
```

---

## 8. Debugging CNI

```bash
# CNI logs (location varies by plugin)
journalctl -u kubelet | grep cni
cat /var/log/calico/cni/cni.log
cat /var/log/aws-routed-eni/ipamd.log

# Manually run a CNI plugin (simulate ADD)
export CNI_COMMAND=ADD
export CNI_CONTAINERID=test-container
export CNI_NETNS=/var/run/netns/test-ns
export CNI_IFNAME=eth0
export CNI_PATH=/opt/cni/bin

ip netns add test-ns
echo '{"cniVersion":"1.0.0","name":"test","type":"bridge","bridge":"cni-test","ipam":{"type":"host-local","ranges":[[{"subnet":"10.99.0.0/24"}]]}}' \
  | /opt/cni/bin/bridge

# Common CNI failure modes:
# 1. Binary not found in CNI_PATH
# 2. Network namespace not created yet
# 3. IPAM pool exhausted (host-local: check /var/lib/cni/networks/)
# 4. Interface name conflict (eth0 already exists in namespace)
# 5. Missing kernel modules (vxlan, bridge)

# Check if kernel modules are loaded
lsmod | grep -E "vxlan|bridge|8021q"
modprobe bridge vxlan
```

---

## 9. CNI Plugin Comparison

| Plugin | Overlay | BGP | NetworkPolicy | eBPF | Cloud Support |
|--------|---------|-----|--------------|------|--------------|
| Flannel | VXLAN/host-gw | No | No (needs plugin) | No | Yes |
| Calico | VXLAN/IP-IP | Yes | Yes | Yes (eBPF mode) | Yes |
| Cilium | VXLAN/Geneve | No (uses eBPF) | Yes | Yes | Yes |
| Weave | VXLAN mesh | No | Yes | No | Yes |
| AWS VPC CNI | No (native) | No | Via SGs | Possible | AWS only |
| Azure CNI | No/Overlay | No | Via NSG | Cilium option | Azure only |

---

## 10. Summary

| Concept | Detail |
|---------|--------|
| CNI binary location | `/opt/cni/bin/` |
| CNI config location | `/etc/cni/net.d/` |
| Triggered by | kubelet on pod ADD/DEL/CHECK |
| IPAM | Subplugin handling IP allocation |
| Multus | Meta-CNI for multiple interfaces per pod |
| Debug | CNI logs + manual binary execution |

---

**Next:** [Lesson 10 — eBPF and XDP](10-ebpf-xdp.md)
