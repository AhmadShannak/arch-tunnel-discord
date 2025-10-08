#!/usr/bin/env bash
# discord-tunnel.sh — Run Discord only through WireGuard, daemonised and self-cleaning
# Usage: ./discord-tunnel.sh [WG_INTERFACE]
# Default WireGuard interface: wg-ws

set -euo pipefail

WG_IF="${1:-wg-ws}"
NS="discordns"
SUBNET="10.200.0.0/24"
HOST_IP="10.200.0.1"
NS_IP="10.200.0.2"
VETH_HOST="veth-discord"
VETH_NS="vpeer-discord"
NFT_TABLE="discord"
NETNS_DIR="/etc/netns/${NS}"
RESOLV="${NETNS_DIR}/resolv.conf"
LOGFILE="${HOME}/.local/share/discord-tunnel.log"

mkdir -p "$(dirname "$LOGFILE")"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" | tee -a "$LOGFILE"; exit 1; }; }
for cmd in ip nft wg curl firejail xhost nohup; do require_cmd "$cmd"; done

echo "[$(date '+%F %T')] Starting Discord tunnel..." | tee "$LOGFILE"

cleanup() {
  echo "[$(date '+%F %T')] Cleaning up..." | tee -a "$LOGFILE"
  sudo nft list table inet "$NFT_TABLE" >/dev/null 2>&1 && sudo nft delete table inet "$NFT_TABLE" || true
  ip link show "$VETH_HOST" >/dev/null 2>&1 && sudo ip link del "$VETH_HOST" || true
  ip netns list 2>/dev/null | grep -q "^${NS}\b" && sudo ip netns delete "$NS" || true
  echo "[$(date '+%F %T')] Cleanup done." | tee -a "$LOGFILE"
}

# remove any stale state
sudo nft list table inet "$NFT_TABLE" >/dev/null 2>&1 && sudo nft delete table inet "$NFT_TABLE" || true
ip link show "$VETH_HOST" >/dev/null 2>&1 && sudo ip link del "$VETH_HOST" || true
ip netns list 2>/dev/null | grep -q "^${NS}\b" && sudo ip netns delete "$NS" || true

# bring up WireGuard
if ! ip link show dev "$WG_IF" >/dev/null 2>&1; then
  echo "[$(date '+%F %T')] Bringing up WireGuard $WG_IF" | tee -a "$LOGFILE"
  sudo wg-quick up "$WG_IF"
fi

# namespace + veth
sudo ip netns add "$NS"
sudo ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
sudo ip link set "$VETH_NS" netns "$NS"
sudo ip addr add "$HOST_IP/24" dev "$VETH_HOST"
sudo ip link set "$VETH_HOST" up
sudo ip netns exec "$NS" ip addr add "$NS_IP/24" dev "$VETH_NS"
sudo ip netns exec "$NS" ip link set "$VETH_NS" up
sudo ip netns exec "$NS" ip link set lo up
sudo ip netns exec "$NS" ip route add default via "$HOST_IP"

# DNS
sudo mkdir -p "$NETNS_DIR"
echo "nameserver 1.1.1.1" | sudo tee "$RESOLV" >/dev/null

# forwarding + nftables
sudo sysctl -q net.ipv4.ip_forward=1
sudo nft add table inet "$NFT_TABLE"
sudo nft add chain inet "$NFT_TABLE" postrouting '{ type nat hook postrouting priority srcnat; }'
sudo nft add chain inet "$NFT_TABLE" forward '{ type filter hook forward priority filter; }'
sudo nft add rule inet "$NFT_TABLE" postrouting ip saddr "$SUBNET" oif "$WG_IF" masquerade
sudo nft add rule inet "$NFT_TABLE" forward iif "$VETH_HOST" oif "$WG_IF" ct state new,established,related accept
sudo nft add rule inet "$NFT_TABLE" forward iif "$WG_IF" oif "$VETH_HOST" ct state established,related accept

# GUI access
xhost +si:localuser:"$USER" >/dev/null

# background monitor
(
  trap cleanup EXIT
  echo "[$(date '+%F %T')] Launching Discord inside namespace..." | tee -a "$LOGFILE"
  firejail --quiet --noprofile --netns="$NS" /usr/bin/discord >/dev/null 2>&1 &
  DISCORD_PID=$!
  echo "[$(date '+%F %T')] Discord PID $DISCORD_PID" | tee -a "$LOGFILE"
  wait $DISCORD_PID
) & disown

echo "[$(date '+%F %T')] Discord running in background. Logs: $LOGFILE"
exit 0
