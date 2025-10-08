#!/bin/bash
set -e

NS="discordns"

echo "[+] Connecting to NordVPN..."
nordvpn connect >/dev/null &

# Wait for the interface to appear
echo "[+] Waiting for VPN tunnel..."
for i in {1..15}; do
  IFACE=$(ip link | grep -Eo 'nordlynx|tun0' | head -n1 || true)
  if [ -n "$IFACE" ]; then
    break
  fi
  sleep 1
done

if [ -z "$IFACE" ]; then
  echo "[-] Could not detect NordVPN interface. Aborting."
  exit 1
fi

echo "[+] Using interface: $IFACE"

# Create namespace
sudo ip netns add $NS
sudo mkdir -p /etc/netns/$NS
sudo cp /etc/resolv.conf /etc/netns/$NS/resolv.conf
sudo ip netns exec $NS ip link set lo up

# Move VPN interface into namespace
sudo ip link set $IFACE netns $NS
sudo ip netns exec $NS ip link set $IFACE up
sudo ip netns exec $NS ip route add default dev $IFACE

echo "[+] Launching Discord inside VPN namespace..."
if command -v flatpak &>/dev/null && flatpak list | grep -q com.discordapp.Discord; then
  sudo ip netns exec $NS flatpak run com.discordapp.Discord &
else
  sudo ip netns exec $NS discord &
fi

DISCORD_PID=$!

# Wait for Discord to exit
wait $DISCORD_PID

echo "[+] Discord closed, cleaning up..."

# Cleanup
sudo ip netns delete $NS || true
nordvpn disconnect >/dev/null || true

echo "[+] Tunnel closed and cleaned up successfully!"
