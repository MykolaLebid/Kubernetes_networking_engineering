#!/usr/bin/env bash
# Run from: minikube ssh (for CNI binary/config checks)
#           Mac terminal (for the kubectl pod-running check — see note below)
#
# USAGE:
#   Step 1 — inside minikube ssh:
#     bash validate-09.sh
#   Step 2 — from Mac terminal (kubectl check):
#     kubectl get pods -A | grep -v Completed | grep Running
#
# Validates: Lesson 09 — CNI Specification and Plugins
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

echo "=== Validating Lesson 09: CNI Spec and Plugins ==="
echo ""

echo "--- CNI binaries ---"
check "CNI binaries directory /opt/cni/bin/ exists" \
  "[ -d /opt/cni/bin ]"
check "At least one CNI binary present in /opt/cni/bin/" \
  "ls /opt/cni/bin/ | grep -qE '.'"

echo ""
echo "--- CNI configuration ---"
check "CNI config directory /etc/cni/net.d/ exists" \
  "[ -d /etc/cni/net.d ]"
check "At least one CNI config file present in /etc/cni/net.d/" \
  "ls /etc/cni/net.d/ | grep -qE '.'"

echo ""
echo "--- Running pods (kubectl required) ---"
echo "  NOTE: This check requires kubectl access from your Mac terminal."
echo "  Run:  kubectl get pods -A | grep -v Completed | grep Running"
echo "  Skipping kubectl check inside minikube ssh."

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
