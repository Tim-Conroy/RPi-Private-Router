#!/usr/bin/env bash
# travel-vpn — switch the travel router's VPN on and off, or check it.
# Installed to /usr/local/sbin/travel-vpn by travel-vpn-setup.sh.
#
#   sudo travel-vpn on       tunnel up, kill switch on (the normal state)
#   sudo travel-vpn off      PORTAL MODE: tunnel down, devices go straight out,
#                            so you can log in to a campground or hotel Wi-Fi page
#   sudo travel-vpn status   tunnel, kill switch and public IP at a glance
set -euo pipefail

WG_IF="wg0"
WAN="wlan0"
ENV="/etc/wireguard/travel-vpn.env"

[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }
[[ -f "$ENV" ]] || { echo "$ENV missing. Run travel-vpn-setup.sh first."; exit 1; }
# shellcheck source=/dev/null
source "$ENV"

nft list chain inet filter direct_access > /dev/null 2>&1 \
  || { echo "Kill-switch firewall not loaded. Install travel-vpn/nftables.conf first."; exit 1; }

set_pihole_upstream() {
  command -v pihole-FTL > /dev/null || return 0
  pihole-FTL --config dns.upstreams "[\"$1\"]" > /dev/null
  pihole reloaddns > /dev/null 2>&1 || true
  echo "    Pi-hole upstream DNS: $1"
}

handshake_age() {
  local ts
  ts=$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -n | tail -1)
  if [[ -z "$ts" || "$ts" == 0 ]]; then echo "none yet"; else echo "$(( $(date +%s) - ts ))s ago"; fi
}

case "${1:-status}" in
  on)
    echo "==> Kill switch ON (devices can only use the tunnel)"
    nft flush chain inet filter direct_access
    echo "==> Starting the tunnel"
    systemctl restart "wg-quick@$WG_IF"
    set_pihole_upstream "$PROVIDER_DNS"
    sleep 5
    echo "    Last handshake: $(handshake_age)"
    echo "Done. Devices on the private Wi-Fi are protected."
    ;;

  off)
    echo "==> Stopping the tunnel"
    systemctl stop "wg-quick@$WG_IF"
    echo "==> PORTAL MODE: kill switch open, devices go straight out over $WAN"
    nft flush chain inet filter direct_access
    nft add rule inet filter direct_access accept
    # Captive portals usually only answer through their own DNS server.
    venue_dns=$(nmcli -g IP4.DNS device show "$WAN" 2>/dev/null | head -1 | cut -d'|' -f1 | tr -d ' ' || true)
    set_pihole_upstream "${venue_dns:-$FALLBACK_DNS}"
    echo
    echo "!!  NOT PROTECTED. Log in to the Wi-Fi page, then run:  sudo travel-vpn on"
    ;;

  status)
    if systemctl is-active --quiet "wg-quick@$WG_IF"; then
      echo "Tunnel:       UP (last handshake $(handshake_age))"
    else
      echo "Tunnel:       DOWN"
    fi
    if nft list chain inet filter direct_access | grep -q accept; then
      echo "Kill switch:  OPEN (portal mode, devices NOT protected)"
    else
      echo "Kill switch:  ON"
    fi
    echo "Public IP:    $(curl -s --max-time 5 https://ifconfig.me || echo 'no answer')"
    ;;

  *)
    echo "Usage: sudo travel-vpn on | off | status"
    exit 1
    ;;
esac
