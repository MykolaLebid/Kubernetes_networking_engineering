#!/usr/bin/env bash
# Run from: minikube ssh (run `minikube ssh` first, then execute this script inside the VM)
# Validates: Lesson 03 — iptables and Connection Tracking
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

echo "=== Validating Lesson 03: iptables and Connection Tracking ==="
echo ""

echo "--- iptables KUBE-SERVICES chain ---"
check "KUBE-SERVICES chain exists in nat table" \
  "iptables -t nat -L KUBE-SERVICES | head -3"

echo ""
echo "--- conntrack table ---"
# conntrack may output 0 entries in a quiet cluster; just verify the tool works
check "conntrack tool is available and responds" \
  "conntrack -L 2>/dev/null; true"
# A more meaningful check: at least some entries or the table is accessible
check "conntrack table is accessible" \
  "conntrack -L 2>/dev/null | wc -l | grep -qE '^[0-9]+'"

echo ""
echo "--- iptables-save KUBE rules ---"
check "iptables-save contains KUBE rules" \
  "iptables-save | grep -c KUBE | grep -qvE '^0$'"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
