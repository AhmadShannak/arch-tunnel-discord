# Discord VPN Tunnel (Arch Linux)

Run Discord only through your WireGuard VPN.  
The script creates an isolated network namespace for Discord, routes all its traffic through WireGuard, and cleans up automatically when Discord closes.

---

## Features

- Runs Discord through WireGuard only  
- Cleans up automatically when closed  
- Works in the background (no open terminal)  
- Logs to `~/.local/share/discord-tunnel.log`

---

## Requirements

Update your system and install dependencies:

```bash
sudo pacman -Syu
sudo pacman -S --needed wireguard-tools nftables firejail discord curl xorg-xhost
```
You’ll need a working WireGuard config, for example `/etc/wireguard/wg-ws.conf.`

Test it:

```sudo wg-quick up wg-ws
curl ifconfig.me      # should show your VPN IP
sudo wg-quick down wg-ws 
```
## Setup

Move the script to a permanent location:
```
sudo mv ~/discord-tunnel.sh /usr/local/bin/discord-tunnel
sudo chmod +x /usr/local/bin/discord-tunnel
```
Allow GUI apps to display from namespaces:
```
xhost +si:localuser:$USER
```

(Optional) create a short alias:

```
echo "alias discord='nohup discord-tunnel >/dev/null 2>&1 & disown'" >> ~/.zshrc
source ~/.zshrc
```
For Bash users, replace .zshrc with .bashrc.

Usage

Launch Discord through the VPN:
```
discord-tunnel
```
or, if you added the alias:
```
discord
```
When you close Discord, all temporary interfaces, namespaces, and rules are automatically removed.
Logs are stored at ~/.local/share/discord-tunnel.log.

## Manual Cleanup

If something gets stuck:
```
sudo ip netns del discordns 2>/dev/null || true
sudo ip link del veth-discord 2>/dev/null || true
sudo nft delete table inet discord 2>/dev/null || true
```

## License

MIT License © 2025
