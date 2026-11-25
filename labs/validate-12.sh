#!/usr/bin/env bash
# Run from: Mac (Terminal 2) — requires kubectl and cilium CLI
# Validates: Lesson 12 — Cilium CNI and eBPF Dataplane
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

echo "=== Validating Lesson 12: Cilium CNI and eBPF Dataplane ==="
echo ""

echo "--- Cilium installation ---"
check "cilium CLI is installed" "command -v cilium"
check "cilium-agent DaemonSet is running" \
  "kubectl get ds -n kube-system cilium -o jsonpath='{.status.numberReady}' | grep -v '^0$'"
check "cilium-operator Deployment is running" \
  "kubectl get deploy -n kube-system cilium-operator -o jsonpath='{.status.readyReplicas}' | grep -v '^0$'"

echo ""
echo "--- Cilium status ---"
check "cilium status reports OK" \
  "cilium status --wait 2>/dev/null | grep -q 'OK\|ok'"
check "No cilium pods in CrashLoopBackOff" \
  "! kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep -q CrashLoop"

echo ""
echo "--- Hubble observability ---"
check "Hubble relay is running" \
  "kubectl get deploy -n kube-system hubble-relay -o jsonpath='{.status.readyReplicas}' | grep -v '^0$'"
check "hubble CLI is installed" "command -v hubble"
check "hubble observe returns flows" \
  "hubble observe --last 5 2>/dev/null | grep -qE 'forwarded|dropped|TCP|UDP'"

echo ""
echo "--- CiliumNetworkPolicy enforcement ---"
check "CiliumNetworkPolicy CRD exists" \
  "kubectl get crd ciliumnetworkpolicies.cilium.io"
check "CiliumClusterwideNetworkPolicy CRD exists" \
  "kubectl get crd ciliumclusterwidenetworkpolicies.cilium.io"

echo ""
echo "--- eBPF dataplane ---"
check "Cilium eBPF programs loaded on node" \
  "kubectl exec -n kube-system ds/cilium -c cilium-agent -- bpftool prog list 2>/dev/null | grep -q sched"
check "Cilium BPF maps present" \
  "kubectl exec -n kube-system ds/cilium -c cilium-agent -- bpftool map list 2>/dev/null | grep -q cilium"

echo ""
echo "--- Identity-based policy ---"
check "At least one CiliumEndpoint exists (pods have identities)" \
  "kubectl get ciliumendpoints -A --no-headers 2>/dev/null | grep -qv '^$'"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
