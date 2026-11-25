#!/usr/bin/env bash
# validate-38.sh — Validate Multus CNI and multi-homed pod setup
# Run from: Terminal 2 (Mac)
set -euo pipefail

PASS=0; FAIL=0

check() {
  local desc="$1"; shift
  if "$@" &>/dev/null; then
    echo "PASS: $desc"; ((PASS++))
  else
    echo "FAIL: $desc"; ((FAIL++))
  fi
}

echo "=== Multus CNI Validation ==="

# 1. Multus DaemonSet present
check "kube-multus-ds DaemonSet exists" \
  kubectl get ds kube-multus-ds -n kube-system

# 2. Multus DaemonSet is ready
DESIRED=$(kubectl get ds kube-multus-ds -n kube-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
READY=$(kubectl get ds kube-multus-ds -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
if [ "$DESIRED" -gt 0 ] && [ "$READY" -eq "$DESIRED" ]; then
  echo "PASS: kube-multus-ds all $READY/$DESIRED nodes ready"; ((PASS++))
else
  echo "FAIL: kube-multus-ds not fully ready ($READY/$DESIRED)"; ((FAIL++))
fi

# 3. NetworkAttachmentDefinition CRD installed
check "NetworkAttachmentDefinition CRD installed" \
  kubectl get crd network-attachment-definitions.k8s.cni.cncf.io

# 4. Can create a NAD
kubectl apply -f - &>/dev/null <<EOF
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: validate-macvlan
  namespace: default
spec:
  config: |
    {"cniVersion":"0.3.1","type":"macvlan","master":"eth0","mode":"bridge","ipam":{"type":"host-local","subnet":"192.168.99.0/24"}}
EOF
check "NAD creation succeeds" kubectl get network-attachment-definition validate-macvlan -n default
kubectl delete network-attachment-definition validate-macvlan -n default &>/dev/null || true

# 5. Multus logs present (not crashing)
check "Multus pods have logs (not crashlooping)" \
  bash -c 'kubectl logs -n kube-system -l app=multus --tail=5 2>/dev/null | grep -q .'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
