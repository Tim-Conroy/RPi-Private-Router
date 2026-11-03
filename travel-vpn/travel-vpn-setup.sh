#!/usr/bin/env bash
# travel-vpn-setup.sh — make the travel Pi a WireGuard CLIENT, so every device on
# the private Wi-Fi (wlan1) goes through an encrypted tunnel.
#
# Usage: sudo ./travel-vpn-setup.sh <wireguard-config.conf>
#
# The config comes from your VPN provider (Proton VPN, Surfshark, ...) or from
# wg-add-client.sh on a home WireGuard server (see ../wireguard).
# Safe to re-run with a new config: the old wg0.conf is backed up first.
set -euo pipefail

SRC="${1:?usage: sudo $0 <wireguard-config.conf>}"
WG_IF="wg0"
CONF="/etc/wireguard/$WG_IF.conf"
ENV="/etc/wireguard/travel-vpn.env"
HERE="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }
[[ -f "$SRC" ]]    || { echo "Config file not found: $SRC"; exit 1; }

# --- 1. Check the config makes sense -------------------------------------
grep -q '^\[Interface\]' "$SRC" && grep -q '^\[Peer\]' "$SRC" \
  || { echo "This doesn't look like a WireGuard config (needs [Interface] and [Peer])."; exit 1; }
grep -qE '^PrivateKey\s*=' "$SRC" || { echo "Config has no PrivateKey."; exit 1; }
grep -qE '^Endpoint\s*=' "$SRC"   || { echo "Config has no Endpoint (the server to connect to)."; exit 1; }
grep -qE '^AllowedIPs\s*=.*0\.0\.0\.0/0' "$SRC" || {
  echo "AllowedIPs does not include 0.0.0.0/0, so this is a split tunnel."
  echo "The kill switch would block everything outside the tunnel. Download a full-tunnel config."
  exit 1
}

endpoint_host=$(grep -oP '^Endpoint\s*=\s*\K[^:\s]+' "$SRC" | head -1)
if [[ ! "$endpoint_host" =~ ^[0-9.]+$ ]]; then
  echo "Note: Endpoint is a hostname ($endpoint_host). The Pi must be able to look it up"
  echo "      when the tunnel starts. If the tunnel fails at boot, use a config with an IP endpoint."
fi

# The provider's DNS server (reachable only inside the tunnel) becomes Pi-hole's upstream.
provider_dns=$(grep -oP '^DNS\s*=\s*\K.*' "$SRC" | tr ',' '\n' | tr -d ' ' \
               | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -1 || true)

# --- 2. Install -----------------------------------------------------------
echo "==> Installing wireguard-tools"
apt-get update
apt-get install -y wireguard-tools

install -d -m 700 /etc/wireguard

if [[ -f "$CONF" ]]; then
  backup="$CONF.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$CONF" "$backup"
  echo "==> Existing $CONF backed up to $backup"
fi

# --- 3. Write wg0.conf ----------------------------------------------------
# The DNS line is removed: Pi-hole handles DNS for the whole network, and on
# Trixie wg-quick would otherwise need resolvconf.
echo "==> Writing $CONF"
(umask 077; grep -vE '^DNS\s*=' "$SRC" > "$CONF")
chown root:root "$CONF"

# Starlink (and most travel Wi-Fi) puts you behind CGNAT, which forgets idle
# connections. A keepalive every 25 s stops the tunnel from going silent.
if ! grep -qE '^PersistentKeepalive\s*=' "$CONF"; then
  sed -i '/^\[Peer\]/a PersistentKeepalive = 25' "$CONF"
  echo "==> Added PersistentKeepalive = 25 (keeps the tunnel open through Starlink's CGNAT)"
fi

(umask 077; cat > "$ENV" <<EOF
# Read by travel-vpn. Pi-hole's upstream DNS while the tunnel is on:
PROVIDER_DNS="${provider_dns:-9.9.9.9}"
# Used in portal mode if the venue's own DNS can't be found:
FALLBACK_DNS="9.9.9.9"
EOF
)

# --- 4. Forwarding, the travel-vpn command, start at boot -----------------
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
sysctl --system > /dev/null

install -m 755 "$HERE/travel-vpn.sh" /usr/local/sbin/travel-vpn
echo "==> Installed the 'travel-vpn' command (on / off / status)"

systemctl enable "wg-quick@$WG_IF" > /dev/null
echo "==> Tunnel set to start at boot"

if [[ -z "$provider_dns" ]]; then
  echo "Note: the config had no DNS line, so Pi-hole will use 9.9.9.9 through the tunnel."
fi

# --- 5. Turn it on, if the kill-switch firewall is already in place --------
if nft list chain inet filter direct_access > /dev/null 2>&1; then
  /usr/local/sbin/travel-vpn on
  echo
  echo "Next: lock the Pi down with  sudo ./harden.sh  then run  sudo travel-vpn check"
else
  echo
  echo "Next: install the kill-switch firewall from nftables.conf, then run:  sudo travel-vpn on"
fi
