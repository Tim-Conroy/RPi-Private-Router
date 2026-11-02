#!/usr/bin/env bash
# wg-server-setup.sh — install and start a WireGuard server on a Raspberry Pi 5 (Debian/RPi OS Trixie)
# Usage: sudo ./wg-server-setup.sh
# Safe to re-run: existing keys and wg0.conf are never overwritten.
set -euo pipefail

WG_IF="wg0"
WG_ADDR="10.10.0.1/24"   # VPN subnet; pick one that doesn't clash with your LAN
WG_PORT="51820"

[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }

echo "==> Installing wireguard-tools and qrencode"
apt-get update
apt-get install -y wireguard-tools qrencode

install -d -m 700 /etc/wireguard /etc/wireguard/clients
cd /etc/wireguard

if [[ ! -f server.key ]]; then
  echo "==> Generating server keys"
  (umask 077; wg genkey > server.key)
  wg pubkey < server.key > server.pub
else
  echo "==> Server keys already exist, keeping them"
fi

if [[ ! -f "$WG_IF.conf" ]]; then
  echo "==> Writing /etc/wireguard/$WG_IF.conf"
  (umask 077; cat > "$WG_IF.conf" <<EOF
[Interface]
Address = $WG_ADDR
ListenPort = $WG_PORT
PrivateKey = $(cat server.key)
# Firewall/NAT rules live in /etc/nftables.conf, not PostUp/PostDown.
# Client [Peer] sections are appended by wg-add-client.sh
EOF
)
else
  echo "==> $WG_IF.conf already exists, not overwriting"
fi

echo "==> Making sure IPv4 forwarding is on"
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
sysctl --system > /dev/null

echo "==> Enabling wg-quick@$WG_IF at boot and starting it"
systemctl enable --now "wg-quick@$WG_IF"

echo
wg show "$WG_IF"
echo
echo "Server public key: $(cat server.pub)"
echo "Next: add the WireGuard rules to /etc/nftables.conf, then run wg-add-client.sh"
