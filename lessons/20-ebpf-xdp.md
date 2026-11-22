# Lesson 20 — eBPF and XDP in Kubernetes Networking

> **Track:** Network Foundation — Bare Metal & Cloud  
> **Prerequisites:** [Lesson 11 — Cilium](11-cilium-cni-ebpf.md), [Lesson 03 — iptables](03-iptables-and-netfilter.md)  
> **Duration:** ~2.5 hours

---

## Why This Matters

eBPF is transforming Kubernetes networking the same way containers transformed deployment. It enables observability, security enforcement, and load balancing at kernel speed — without kernel modules or application changes. Understanding eBPF lets you reason about Cilium internals, write custom packet filters, and unlock performance impossible with iptables.

---

## 1. What eBPF Is

eBPF (extended Berkeley Packet Filter) is a sandboxed virtual machine in the Linux kernel. You write programs in a restricted C-like language, compile them to eBPF bytecode, and attach them to kernel hook points. The kernel verifier checks programs for safety before loading.

```
User Space          Kernel Space
─────────────       ─────────────────────────────────────────
eBPF program   →    Verifier → JIT compiler → native code
(C code)            ↓
                    Hook points:
                    XDP, TC, kprobes, tracepoints, sockets...
                              ↓
                    eBPF Maps (shared state: kernel ↔ userspace)
```

---

## 2. eBPF Hook Points

| Hook | Location | Use in Kubernetes |
|------|----------|-----------------|
| XDP | NIC/driver receive path | DDoS filter, L4 LB, fast packet drop |
| TC (ingress/egress) | Traffic Control hook | Cilium network policy, service LB |
| Socket | L4 socket layer | Cilium socket-level LB (bypass stack) |
| kprobe/tracepoint | Kernel function entry | Tetragon security events, debugging |
| LSM | Linux Security Module | Tetragon/Falco security enforcement |

---

## 3. XDP — eXpress Data Path

XDP runs before the kernel allocates an `sk_buff`. Fastest possible hook.

```c
// Simple XDP program: drop all ICMP
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/icmp.h>
#include <bpf/bpf_helpers.h>

SEC("xdp")
int xdp_drop_icmp(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return XDP_PASS;
    if (eth->h_proto != htons(ETH_P_IP)) return XDP_PASS;

    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end) return XDP_PASS;
    if (ip->protocol == IPPROTO_ICMP) return XDP_DROP;

    return XDP_PASS;
}

char LICENSE[] SEC("license") = "GPL";
```

```bash
# Compile with clang
clang -O2 -target bpf -c xdp_drop_icmp.c -o xdp_drop_icmp.o

# Attach to interface
ip link set dev eth0 xdp obj xdp_drop_icmp.o sec xdp

# Detach
ip link set dev eth0 xdp off

# Check attached program
ip link show eth0 | grep xdp
bpftool net show dev eth0
```

XDP return codes:
```
XDP_DROP    — discard packet immediately (fastest)
XDP_PASS    — continue to normal network stack
XDP_TX      — transmit packet back out the same NIC
XDP_REDIRECT — redirect to another NIC or CPU
XDP_ABORTED — program error (like XDP_DROP + trace)
```

---

## 4. TC Hook Programs

TC (Traffic Control) hooks run after sk_buff allocation, allowing full packet manipulation.

```c
// TC egress: add a custom header
SEC("tc")
int tc_egress(struct __sk_buff *skb) {
    // Read packet data
    void *data = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    // ... packet manipulation
    return TC_ACT_OK;
}
```

```bash
# Attach TC eBPF program
tc qdisc add dev eth0 clsact
tc filter add dev eth0 egress bpf da obj tc_prog.o sec tc

# View TC filters
tc filter show dev eth0 egress

# Cilium uses TC for all its per-pod programs
# View Cilium TC programs:
bpftool net show | grep cilium
```

---

## 5. eBPF Maps

Maps are key-value stores shared between kernel eBPF programs and userspace.

```c
// Define a map in eBPF program
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 10000);
    __type(key, __u32);    // IP address
    __type(value, __u64);  // packet counter
} ip_counts SEC(".maps");
```

```bash
# List all eBPF maps
bpftool map list

# Inspect a map
bpftool map dump id <map-id>

# Cilium maps
cilium bpf map list
# Examples:
# cilium_lxc          — per-pod info (IP, MAC, endpoint ID)
# cilium_policy       — compiled policy rules
# cilium_lb4_services — service VIP → backend mapping
# cilium_ct_tcp4      — connection tracking
# cilium_nat          — NAT table

# View Cilium LB service map
cilium bpf lb list
```

---

## 6. eBPF in Cilium — The Full Picture

```
Incoming packet on eth0:
  ↓
  XDP hook (optional — DDoS, early drop)
  ↓
  TC ingress (cilium_netdev program)
    ├── Tail call: policy enforcement
    ├── Tail call: service load balancing (DNAT)
    └── Tail call: conntrack lookup
  ↓
  Kernel routing (or skipped via bpf_redirect)
  ↓
  TC egress on pod's veth (cali* equivalent: lxc* in Cilium)
    └── Policy check for egress
  ↓
  Pod receives packet

For pod → external:
  TC egress on pod veth → policy → NAT if needed → eth0
```

```bash
# View all Cilium eBPF programs loaded
bpftool prog list | grep -i cilium | wc -l
# Expect hundreds of programs on a node with many pods

# View program attached to a specific interface
bpftool net show dev lxc1234abcd
```

---

## 7. Tetragon — eBPF Security

Tetragon enforces security policies at the kernel level using LSM and kprobes.

```bash
# Install Tetragon
helm repo add cilium https://helm.cilium.io/
helm install tetragon cilium/tetragon \
  --namespace kube-system

# Watch all process executions
kubectl exec -n kube-system ds/tetragon -- \
  tetra getevents -o compact | grep exec

# Watch network connections
kubectl exec -n kube-system ds/tetragon -- \
  tetra getevents -o compact | grep connect
```

```yaml
# TracingPolicy — alert on suspicious syscalls
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: detect-exec
spec:
  kprobes:
    - call: "sys_execve"
      syscall: true
      args:
        - index: 0
          type: "string"
      selectors:
        - matchArgs:
            - index: 0
              operator: "Equal"
              values:
                - "/bin/bash"
                - "/bin/sh"
          matchActions:
            - action: Sigkill   # kill the process
```

---

## 8. bpftool — Essential Debug Tool

```bash
# List all loaded programs
bpftool prog list

# Show program details
bpftool prog show id <id>

# Dump eBPF bytecode (before JIT)
bpftool prog dump xlated id <id>

# Dump JIT-compiled machine code
bpftool prog dump jited id <id>

# Profile eBPF program performance
bpftool prog profile id <id> duration 5

# List all maps
bpftool map list

# Dump a map's contents
bpftool map dump id <map-id>

# Update a map entry
bpftool map update id <map-id> key hex 0a f4 00 06 value hex 00 01

# View eBPF programs on network interfaces
bpftool net list
```

---

## 9. eBPF Kernel Requirements

```bash
# Check kernel version (5.4+ recommended, 5.10+ for all Cilium features)
uname -r

# Check eBPF feature support
bpftool feature probe

# Check BPF filesystem is mounted
mount | grep bpf
# bpf on /sys/fs/bpf type bpf

# Mount if missing
mount -t bpf bpf /sys/fs/bpf

# Check for required kernel config
grep -E "CONFIG_BPF|CONFIG_XDP|CONFIG_NET_CLS_BPF" /boot/config-$(uname -r)
```

---

## 10. Summary

| Technology | Use Case in Kubernetes |
|-----------|----------------------|
| XDP | DDoS mitigation, fast packet drop, L4 LB offload |
| TC hook | Cilium policy, service LB, conntrack |
| Socket hook | Socket-level LB (avoid loopback for intra-node) |
| eBPF maps | Shared state: service tables, policy, conntrack |
| Tetragon | Security: exec/connect enforcement, audit logging |
| bpftool | Inspect programs, maps, profiles |

---

**Next:** [Lesson 21 — IPv6 and Dual-Stack Kubernetes](21-ipv6-dual-stack.md)
