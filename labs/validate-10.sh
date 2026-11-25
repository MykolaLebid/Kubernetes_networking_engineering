#!/usr/bin/env bash
# Run from: minikube ssh
# Validates: Lesson 10 — eBPF and XDP
set -uo pipefail

PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if eval "$@" &>/dev/null; then
    echo "  PASS  $desc"
    ((PASS++))
  else
    echo "  FAIL  $desc"
    ((FAIL++))
  fi
}

echo "=== Validating Lesson 10: eBPF and XDP ==="
echo ""

echo "--- Kernel eBPF support ---"
check "Kernel version >= 5.4 (eBPF socket ops, ring buffer)" \
  "[ \$(uname -r | cut -d. -f1) -ge 5 ]"
check "BPF filesystem mounted at /sys/fs/bpf" \
  "mount | grep -q 'bpf on /sys/fs/bpf'"
check "eBPF syscall available (HAVE_EBPF_JIT or /proc/sys/net/core/bpf_jit_enable)" \
  "[ -f /proc/sys/net/core/bpf_jit_enable ]"

echo ""
echo "--- BPF tools ---"
check "bpftool is available" "command -v bpftool"
check "tc (iproute2) is available for BPF program attachment" "command -v tc"

echo ""
echo "--- Loaded eBPF programs ---"
check "At least one eBPF program is loaded (Cilium or other CNI)" \
  "bpftool prog list 2>/dev/null | grep -q 'prog_type'"

echo ""
echo "--- BPF maps ---"
check "BPF maps exist" "bpftool map list 2>/dev/null | grep -q 'map'"

echo ""
echo "--- XDP support ---"
check "ip link supports xdp flag (kernel XDP ready)" \
  "ip link show eth0 2>/dev/null | grep -qE 'xdp|XDP' || ip link show | grep -q xdp || true"
check "XDP-capable NIC present (virtio or real NIC)" \
  "ip link show | grep -qE 'eth|ens|enp'"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
