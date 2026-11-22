#!/usr/bin/env bash
# Run from: Mac terminal (kubectl)
# Validates: Lesson 16 — Kubernetes NetworkPolicy
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

echo "=== Validating Lesson 16: NetworkPolicy ==="
echo ""

# ---------------------------------------------------------------------------
# 1. At least one NetworkPolicy exists in the cluster
# ---------------------------------------------------------------------------
echo "--- NetworkPolicy presence ---"
check "At least one NetworkPolicy exists across all namespaces" \
  "kubectl get networkpolicy -A | grep -v NAME"

# ---------------------------------------------------------------------------
# 2. A default-deny policy exists
#    A default-deny policy has an empty podSelector ({}) and no ingress/egress
#    rules (or an explicit empty list).  We detect it by looking for a policy
#    whose JSON has an empty podSelector and either no policyTypes key or
#    policyTypes containing Ingress.
# ---------------------------------------------------------------------------
echo ""
echo "--- Default-deny policy ---"

# Fetch all network policies as JSON and pipe through python3 (available on
# macOS) to inspect the structure.  We look for a policy where:
#   .spec.podSelector == {}   AND
#   (.spec.ingress is missing or empty)
check "A default-deny ingress policy exists (empty podSelector + no ingress rules)" \
  "kubectl get networkpolicy -A -o json | \
   python3 -I -c \"
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    spec = item.get('spec', {})
    ps   = spec.get('podSelector', {})
    ml   = ps.get('matchLabels', {})
    me   = ps.get('matchExpressions', [])
    # podSelector must be empty
    if ml or me:
        continue
    # ingress must be absent or empty list
    ingress = spec.get('ingress', None)
    if ingress is None or ingress == []:
        print('found:', item['metadata']['namespace'], '/', item['metadata']['name'])
        sys.exit(0)
sys.exit(1)
\""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed!" \
  || { echo "Some checks failed — review the output above"; exit 1; }
