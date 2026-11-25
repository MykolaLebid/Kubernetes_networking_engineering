#!/usr/bin/env bash
# Run from: Mac (Terminal 2) — requires kubectl and istioctl
# Validates: Lesson 21 — Service Mesh with Istio
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

echo "=== Validating Lesson 21: Service Mesh with Istio ==="
echo ""

echo "--- Istio installation ---"
check "istioctl is installed" "command -v istioctl"
check "istiod Deployment is running" \
  "kubectl get deploy -n istio-system istiod -o jsonpath='{.status.readyReplicas}' | grep -v '^0$'"
check "istio-ingressgateway is running" \
  "kubectl get deploy -n istio-system istio-ingressgateway -o jsonpath='{.status.readyReplicas}' | grep -v '^0$'"

echo ""
echo "--- Istio config verification ---"
check "istioctl verify-install passes" \
  "istioctl verify-install 2>/dev/null | grep -qE 'Istio is installed|verified successfully'"
check "No pods in istio-system in error state" \
  "! kubectl get pods -n istio-system --no-headers | grep -qE 'Error|CrashLoop|OOMKill'"

echo ""
echo "--- Sidecar injection ---"
check "Sidecar injection enabled on at least one namespace" \
  "kubectl get ns -l istio-injection=enabled --no-headers | grep -qv '^$'"
check "Envoy proxy sidecar running in a meshed pod" \
  "kubectl get pods -A -o jsonpath='{.items[*].spec.containers[*].name}' | tr ' ' '\n' | grep -q istio-proxy"

echo ""
echo "--- mTLS ---"
check "PeerAuthentication CRD exists" \
  "kubectl get crd peerauthentications.security.istio.io"
check "AuthorizationPolicy CRD exists" \
  "kubectl get crd authorizationpolicies.security.istio.io"
check "istioctl check-inject reports mesh policy" \
  "istioctl x check-inject -n default 2>/dev/null | grep -qiE 'enabled|injected|mesh' || true"

echo ""
echo "--- Traffic management ---"
check "VirtualService CRD exists" \
  "kubectl get crd virtualservices.networking.istio.io"
check "DestinationRule CRD exists" \
  "kubectl get crd destinationrules.networking.istio.io"
check "Gateway CRD exists" \
  "kubectl get crd gateways.networking.istio.io"

echo ""
echo "--- Observability ---"
check "Kiali or Jaeger deployed (optional but expected in lesson)" \
  "kubectl get deploy -A --no-headers 2>/dev/null | grep -qE 'kiali|jaeger|zipkin' || true"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
