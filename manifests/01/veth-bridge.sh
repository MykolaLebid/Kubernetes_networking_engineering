#!/usr/bin/env bash
# veth-bridge.sh
# Simulates Kubernetes pod-to-pod networking using Linux network namespaces,
# a veth pair, and a bridge device. Each namespace represents a "pod" with its
# own IP address. Run as root or with sudo.
#
# Topology:
#   ns1 (10.0.0.11) <--veth1--> bridge0 (10.0.0.1) <--veth2--> ns2 (10.0.0.12)

set -euo pipefail

BRIDGE="bridge0"
NS1="ns1"
NS2="ns2"
BRIDGE_IP="10.0.0.1/24"
NS1_IP="10.0.0.11/24"
NS2_IP="10.0.0.12/24"

cleanup() {
  echo "[cleanup] Removing namespaces and bridge..."
  ip netns del "$NS1" 2>/dev/null || true
  ip netns del "$NS2" 2>/dev/null || true
  ip link del "$BRIDGE" 2>/dev/null || true
}

# Uncomment to auto-clean on exit
# trap cleanup EXIT

echo "[1/6] Creating bridge: $BRIDGE"
ip link add "$BRIDGE" type bridge
ip addr add "$BRIDGE_IP" dev "$BRIDGE"
ip link set "$BRIDGE" up

echo "[2/6] Creating network namespaces: $NS1 and $NS2"
ip netns add "$NS1"
ip netns add "$NS2"

echo "[3/6] Creating veth pairs and attaching to bridge"
# veth pair for ns1
ip link add veth1-host type veth peer name veth1-ns
ip link set veth1-host master "$BRIDGE"
ip link set veth1-host up
ip link set veth1-ns netns "$NS1"

# veth pair for ns2
ip link add veth2-host type veth peer name veth2-ns
ip link set veth2-host master "$BRIDGE"
ip link set veth2-host up
ip link set veth2-ns netns "$NS2"

echo "[4/6] Configuring interfaces inside namespaces"
ip netns exec "$NS1" ip addr add "$NS1_IP" dev veth1-ns
ip netns exec "$NS1" ip link set veth1-ns up
ip netns exec "$NS1" ip link set lo up
ip netns exec "$NS1" ip route add default via 10.0.0.1

ip netns exec "$NS2" ip addr add "$NS2_IP" dev veth2-ns
ip netns exec "$NS2" ip link set veth2-ns up
ip netns exec "$NS2" ip link set lo up
ip netns exec "$NS2" ip route add default via 10.0.0.1

echo "[5/6] Enabling IP forwarding"
sysctl -w net.ipv4.ip_forward=1 > /dev/null

echo "[6/6] Testing connectivity"
echo "  ns1 -> ns2 ping:"
ip netns exec "$NS1" ping -c 3 10.0.0.12

echo "  ns2 -> ns1 ping:"
ip netns exec "$NS2" ping -c 3 10.0.0.11

echo ""
echo "Setup complete. To clean up, run:"
echo "  sudo ip netns del $NS1; sudo ip netns del $NS2; sudo ip link del $BRIDGE"
