#!/usr/bin/env bash
# Run from: Mac terminal (kubectl)
# Validates: Lesson 13 — Kubernetes Services and kube-proxy
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

echo "=== Validating Lesson 13: Kubernetes Services ==="
echo ""

# ---------------------------------------------------------------------------
# 1. ClusterIP service exists (any namespace)
# ---------------------------------------------------------------------------
echo "--- ClusterIP service ---"
check "At least one ClusterIP service exists" \
  "kubectl get svc -A -o jsonpath='{.items[*].spec.type}' | tr ' ' '\n' | grep -q ClusterIP"

# ---------------------------------------------------------------------------
# 2. KUBE-SERVICES iptables chain (via kubectl exec on a privileged pod)
#
#    Strategy: look for a privileged daemonset pod (e.g. kube-proxy) that
#    already has iptables access, rather than launching a new pod.
# ---------------------------------------------------------------------------
echo ""
echo "--- KUBE-SERVICES iptables chain ---"

# Try kube-proxy pod first (it always has iptables access in minikube)
PROXY_POD=$(kubectl get pod -n kube-system -l k8s-app=kube-proxy \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -n "$PROXY_POD" ]; then
  check "KUBE-SERVICES chain exists (via kube-proxy pod)" \
    "kubectl exec -n kube-system $PROXY_POD -- iptables -t nat -L KUBE-SERVICES"
else
  echo "  SKIP  kube-proxy pod not found; skipping iptables chain check"
  echo "        (create a privileged pod with hostNetwork:true and check manually)"
fi

# ---------------------------------------------------------------------------
# 3. EndpointSlices
# ---------------------------------------------------------------------------
echo ""
echo "--- EndpointSlices ---"
check "At least one EndpointSlice exists" \
  "kubectl get endpointslices -A | grep -v NAME"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
