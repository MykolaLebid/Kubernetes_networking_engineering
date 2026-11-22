#!/usr/bin/env bash
# Run from: Mac terminal (kubectl)
# Validates: Lesson 14 — CoreDNS and Service Discovery
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

echo "=== Validating Lesson 14: CoreDNS and Service Discovery ==="
echo ""

# ---------------------------------------------------------------------------
# 1. CoreDNS pods are running
# ---------------------------------------------------------------------------
echo "--- CoreDNS pods ---"
check "CoreDNS pods are running (k8s-app=kube-dns)" \
  "kubectl get pods -n kube-system -l k8s-app=kube-dns | grep -q Running"

# ---------------------------------------------------------------------------
# 2. kube-dns service exists
# ---------------------------------------------------------------------------
echo ""
echo "--- kube-dns service ---"
check "kube-dns service exists in kube-system" \
  "kubectl get svc -n kube-system kube-dns"

# ---------------------------------------------------------------------------
# 3. DNS resolution works inside a pod
#    Launches a short-lived netshoot pod and runs nslookup kubernetes
# ---------------------------------------------------------------------------
echo ""
echo "--- DNS resolution ---"
echo "  Launching a temporary test pod (nicolaka/netshoot) ..."
check "nslookup kubernetes resolves inside a pod" \
  "kubectl run dns-test-\$\$ \
     --image=nicolaka/netshoot \
     --restart=Never \
     --rm \
     -it \
     --timeout=60s \
     -- nslookup kubernetes 2>&1 | grep -q 'Address'"

# ---------------------------------------------------------------------------
# 4. ndots setting in a pod's resolv.conf
# ---------------------------------------------------------------------------
echo ""
echo "--- resolv.conf ndots setting ---"
check "Pod resolv.conf contains ndots:5 (default Kubernetes setting)" \
  "kubectl run resolv-test-\$\$ \
     --image=busybox:1.36 \
     --restart=Never \
     --rm \
     -it \
     --timeout=60s \
     -- cat /etc/resolv.conf 2>&1 | grep -q 'ndots:5'"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
