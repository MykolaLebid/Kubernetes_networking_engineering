#!/usr/bin/env bash
# Run from: minikube ssh (run `minikube ssh` first, then execute this script inside the VM)
# Validates: Lesson 01 — Linux Networking Fundamentals
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

echo "=== Validating Lesson 01: Linux Networking Fundamentals ==="
echo ""

echo "--- Virtual Ethernet (veth) pairs ---"
check "A veth pair exists in ip link" "ip link | grep veth"

echo ""
echo "--- Linux bridge ---"
check "A Linux bridge interface exists" "ip link show type bridge"

echo ""
echo "--- IP forwarding ---"
check "ip_forward is enabled (value = 1)" \
  "[ \"\$(sysctl -n net.ipv4.ip_forward)\" = '1' ]"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
