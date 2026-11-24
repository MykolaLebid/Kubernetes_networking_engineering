# eBPF Quick Reference

## Program Types

| Type | Hook Point | Use Case |
|------|------------|----------|
| `XDP` | NIC driver / early ingress | DDoS drop, load balancing, DSR |
| `TC` | Traffic Control ingress/egress | Packet mangling, Cilium policy |
| `kprobe/kretprobe` | Kernel function entry/exit | Tracing, profiling |
| `tracepoint` | Static kernel trace events | Stable tracing API |
| `socket_filter` | Socket recv path | Packet capture, filtering |
| `cgroup_skb` | cgroup ingress/egress | Per-pod policy enforcement |
| `sock_ops` | TCP connection events | Latency tracking |
| `sk_msg` | sockmap redirect | Kernel-bypass pod-to-pod |

---

## Map Types

| Map Type | Key → Value | Use Case |
|----------|-------------|----------|
| `BPF_MAP_TYPE_HASH` | arbitrary → arbitrary | Policy lookups, flow state |
| `BPF_MAP_TYPE_ARRAY` | u32 → value | Counters, config |
| `BPF_MAP_TYPE_LPM_TRIE` | CIDR → value | IP prefix routing |
| `BPF_MAP_TYPE_PERF_EVENT_ARRAY` | index → fd | Userspace event streaming |
| `BPF_MAP_TYPE_RINGBUF` | — | Low-overhead event output (5.8+) |
| `BPF_MAP_TYPE_SOCKMAP` | sock → sock | Socket redirect |
| `BPF_MAP_TYPE_CPUMAP` | cpu → queue | XDP CPU steering |
| `BPF_MAP_TYPE_DEVMAP` | ifindex → ifindex | XDP tx redirect |

---

## Program Lifecycle

```mermaid
flowchart LR
    SRC[C Source] -->|clang -target bpf| OBJ[ELF Object]
    OBJ -->|bpf_prog_load| VER[Verifier]
    VER -->|JIT| KERN[Kernel]
    KERN -->|attach| HOOK[Hook Point]
    HOOK <-->|read/write| MAP[BPF Maps]
    MAP -->|fd / bpftool| USR[User Space]
```

---

## bpftool Commands

| Command | Description |
|---------|-------------|
| `bpftool prog list` | List all loaded programs |
| `bpftool prog show id <ID>` | Show program details |
| `bpftool prog dump xlated id <ID>` | Dump translated bytecode |
| `bpftool prog dump jited id <ID>` | Dump JIT-compiled instructions |
| `bpftool map list` | List all maps |
| `bpftool map dump id <ID>` | Dump full map contents |
| `bpftool map lookup id <ID> key <hex>` | Lookup single entry |
| `bpftool net list` | TC/XDP programs on interfaces |
| `bpftool cgroup list /sys/fs/cgroup/` | cgroup-attached programs |
| `bpftool btf list` | List BTF type info objects |

---

## XDP Return Codes

| Code | Action |
|------|--------|
| `XDP_PASS` | Forward packet up the stack |
| `XDP_DROP` | Drop silently (fastest path) |
| `XDP_TX` | Redirect out same interface |
| `XDP_REDIRECT` | Forward to another iface/CPU |
| `XDP_ABORTED` | Drop + trace event (debug) |

---

## Cilium eBPF Features

- **Kube-proxy replacement** — Service LB via `BPF_MAP_TYPE_LRU_HASH`; no iptables
- **Host routing** — packets bypass netfilter; routed entirely in BPF
- **Sockmap acceleration** — same-node pod-to-pod via `sk_msg`; bypasses TCP stack
- **Network Policy** — enforced per-pod at `cgroup_skb` hook
- **Hubble** — flow metadata streamed via `BPF_MAP_TYPE_RINGBUF` / perf events
- **Bandwidth Manager** — TC egress rate limiting per pod
- **XDP load balancer** — optional `XDP_TX` for Direct Server Return (DSR)
- **Encryption** — WireGuard or IPsec triggered by BPF policy lookup

## Cilium CLI — eBPF Inspection

| Command | Description |
|---------|-------------|
| `cilium status` | Health + BPF feature flags |
| `cilium bpf policy get <ep-id>` | BPF policy map for a pod |
| `cilium bpf ct list global` | Connection tracking table |
| `cilium bpf lb list` | Service entries (kube-proxy replacement) |
| `cilium bpf nat list` | SNAT/DNAT map |
| `cilium bpf endpoint list` | endpoint → IP mappings |
| `cilium monitor` | Live packet event stream |
| `hubble observe` | Flow-level visibility (requires relay) |

---

## BCC vs libbpf

| Aspect | BCC | libbpf + CO-RE |
|--------|-----|----------------|
| Language | Python + C embedded strings | C with BTF headers |
| Portability | Requires kernel headers at runtime | Runs on any BTF-enabled kernel |
| Compilation | JIT at load time | Ahead-of-time (portable ELF) |
| Overhead | High (LLVM at load) | Low |
| Use case | Rapid prototyping / tracing | Production / Cilium internals |
| Tools | bcc-tools, bpftrace | Cilium, Katran, XDP-tools |

---

## Kernel Version Requirements

- **4.1+** — eBPF base support
- **4.19 / 5.1+** — Cilium minimum (5.10+ recommended)
- **5.2+** — BTF + CO-RE portability
- **5.8+** — `BPF_MAP_TYPE_RINGBUF`
- **5.18+** — XDP multi-buffer support

→ Full lessons: [Lesson 10 — eBPF & XDP](../lessons/10-ebpf-xdp.md) · [Lesson 12 — Cilium CNI & eBPF](../lessons/12-cilium-cni-ebpf.md)
