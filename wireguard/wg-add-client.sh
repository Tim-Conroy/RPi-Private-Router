#!/usr/bin/env bash
# wg-add-client.sh — create a WireGuard client (phone/laptop) and show its QR code
# Usage: sudo ./wg-add-client.sh <client-name> <endpoint-hostname>
# Example: sudo ./wg-add-client.sh phone myhome.duckdns.org
set -euo pipefail

NAME="${1:?usage: sudo $0 <client-name> <endpoint-hostname>}"
ENDPOINT_HOST="${2:?usage: sudo $0 <client-name> <endpoint-hostname>}"

WG_IF="wg0"
WG_PORT="51820"
WG_NET="10.10.0"          # first three octets of the VPN subnet
DNS="10.10.0.1"           # the Pi itself = Pi-hole
CONF="/etc/wireguard/$WG_IF.conf"
CDIR="/etc/wireguard/clients"

[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }
[[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Client name: letters, numbers, - and _ only."; exit 1; }
[[ -f "$CONF" ]] || { echo "$CONF not found. Run wg-server-setup.sh first."; exit 1; }
[[ ! -e "$CDIR/$NAME.conf" ]] || { echo "Client '$NAME' already exists."; exit 1; }

# Next free address: highest existing .X in wg0.conf + 1 (server is .1, first client .2)
last=$(grep -oP "AllowedIPs\s*=\s*${WG_NET//./\\.}\.\K[0-9]+" "$CONF" | sort -n | tail -1 || true)
next=$(( ${last:-1} + 1 ))
(( next < 255 )) || { echo "VPN subnet is full."; exit 1; }

umask 077
priv=$(wg genkey)
pub=$(echo "$priv" | wg pubkey)
psk=$(wg genpsk)

# 1) Add the client as a peer on the server
cat >> "$CONF" <<EOF

[Peer]
# $NAME
PublicKey = $pub
PresharedKey = $psk
AllowedIPs = $WG_NET.$next/32
EOF

# 2) Write the client's own config
cat > "$CDIR/$NAME.conf" <<EOF
[Interface]
PrivateKey = $priv
Address = $WG_NET.$next/32
DNS = $DNS

[Peer]
PublicKey = $(cat /etc/wireguard/server.pub)
PresharedKey = $psk
Endpoint = $ENDPOINT_HOST:$WG_PORT
# Full tunnel: send ALL traffic home. ::/0 also captures IPv6 so it can't leak around the VPN.
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

# 3) Load the new peer without dropping existing connections
wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")

echo "Client '$NAME' -> $WG_NET.$next  (config: $CDIR/$NAME.conf)"
echo "Scan this with the WireGuard app (+ > Scan from QR code):"
echo
qrencode -t ansiutf8 < "$CDIR/$NAME.conf"
