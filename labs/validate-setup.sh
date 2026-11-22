#!/usr/bin/env bash
# Run from: Mac terminal — run BEFORE starting the course to verify your environment
# Validates: Course environment setup
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

echo "=== Validating Course Environment Setup ==="
echo ""

# ---------------------------------------------------------------------------
# 1. minikube is running
# ---------------------------------------------------------------------------
echo "--- minikube ---"
check "minikube is running" \
  "minikube status | grep -q 'host: Running'"

# ---------------------------------------------------------------------------
# 2. kubectl is configured and can reach the cluster
# ---------------------------------------------------------------------------
echo ""
echo "--- kubectl ---"
check "kubectl is installed" \
  "command -v kubectl"
check "kubectl cluster-info succeeds" \
  "kubectl cluster-info"

# ---------------------------------------------------------------------------
# 3. minikube ssh works
# ---------------------------------------------------------------------------
echo ""
echo "--- minikube ssh ---"
check "minikube ssh is functional (uname -r returns a kernel version)" \
  "minikube ssh 'uname -r' | grep -qE '^[0-9]+\.[0-9]+'"

# ---------------------------------------------------------------------------
# 4. bpftool availability inside minikube
# ---------------------------------------------------------------------------
echo ""
echo "--- bpftool (eBPF lessons) ---"
BPFTOOL_OUT=$(minikube ssh 'which bpftool || echo missing' 2>/dev/null || echo missing)
if echo "$BPFTOOL_OUT" | grep -q missing; then
  echo "  WARN  bpftool not found in minikube (eBPF lessons will need manual install)"
  echo "        Install with:  minikube ssh 'sudo apt-get install -y linux-tools-common linux-tools-generic'"
else
  echo "  PASS  bpftool is available in minikube ($BPFTOOL_OUT)"
  ((PASS++))
fi

# ---------------------------------------------------------------------------
# 5. Required Mac-side tools
# ---------------------------------------------------------------------------
echo ""
echo "--- Required Mac-side tools ---"
check "kubectl binary on PATH" \
  "command -v kubectl"
check "helm binary on PATH" \
  "command -v helm"

# ---------------------------------------------------------------------------
# Optional but recommended tools
# ---------------------------------------------------------------------------
echo ""
echo "--- Optional / recommended tools ---"
for tool in curl jq python3 docker; do
  if command -v "$tool" &>/dev/null; then
    echo "  PASS  $tool is available"
  else
    echo "  SKIP  $tool not found (optional)"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] \
  && echo "All checks passed — environment is ready!" \
  || { echo "Some checks failed — fix the issues above before starting the course"; exit 1; }
