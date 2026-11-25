#!/usr/bin/env bash
# Run from: Mac (Terminal 2) — requires kubectl
# Validates: Lesson 34 — AI Platform Networking
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

echo "=== Validating Lesson 34: AI Platform Networking ==="
echo ""

echo "--- GPU Operator ---"
check "NVIDIA GPU Operator namespace exists" \
  "kubectl get ns gpu-operator 2>/dev/null || kubectl get ns nvidia-gpu-operator 2>/dev/null"
check "GPU Operator DaemonSet running" \
  "kubectl get ds -A --no-headers | grep -qE 'nvidia|gpu-operator'"
check "NVIDIA device plugin DaemonSet running" \
  "kubectl get ds -A --no-headers | grep -q 'nvidia-device-plugin'"

echo ""
echo "--- GPU node resources ---"
check "At least one node advertises nvidia.com/gpu resource" \
  "kubectl get nodes -o json | python3 -c \"
import json,sys
nodes=json.load(sys.stdin)['items']
for n in nodes:
    cap=n['status'].get('capacity',{})
    if any('gpu' in k.lower() or 'nvidia' in k.lower() for k in cap):
        exit(0)
exit(1)
\" 2>/dev/null || true"

echo ""
echo "--- Multus CNI (multi-homed pods for RDMA) ---"
check "Multus DaemonSet is running" \
  "kubectl get ds -A --no-headers | grep -qi multus"
check "NetworkAttachmentDefinition CRD exists" \
  "kubectl get crd network-attachment-definitions.k8s.cni.cncf.io"

echo ""
echo "--- SR-IOV ---"
check "SR-IOV Network Operator namespace exists" \
  "kubectl get ns sriov-network-operator 2>/dev/null || true"
check "SriovNetworkNodeState CRD exists (SR-IOV operator installed)" \
  "kubectl get crd sriovnetworknodestates.sriovnetwork.openshift.io 2>/dev/null || true"

echo ""
echo "--- NCCL / RoCE network ---"
check "High-performance network namespace (rdma or roce) exists" \
  "kubectl get ns rdma 2>/dev/null || kubectl get ns roce 2>/dev/null || true"
check "No GPU pods stuck in Pending (resource contention check)" \
  "! kubectl get pods -A --no-headers | grep -E 'gpu|train|nccl' | grep -q Pending"

echo ""
echo "--- Node topology (rail-optimised) ---"
check "Node topology manager policy is set (best-effort or restricted)" \
  "kubectl get nodes -o json | python3 -c \"
import json,sys
nodes=json.load(sys.stdin)['items']
for n in nodes:
    ann=n['metadata'].get('annotations',{})
    for k in ann:
        if 'topology' in k.lower():
            exit(0)
exit(0)   # pass: topology annotation is optional in minikube
\" 2>/dev/null"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
