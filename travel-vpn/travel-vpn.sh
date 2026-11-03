#!/usr/bin/env bash
# travel-vpn — switch the travel router's VPN on and off, or check it.
# Installed to /usr/local/sbin/travel-vpn by travel-vpn-setup.sh.
#
#   sudo travel-vpn on       tunnel up, kill switch on (the normal state)
#   sudo travel-vpn off      PORTAL MODE: tunnel down, devices go straight out,
#                            so you can log in to a campground or hotel Wi-Fi page
#   sudo travel-vpn status   tunnel, kill switch and public IP at a glance
#   sudo travel-vpn check    full security check: PASS / WARN / FAIL for each item
set -euo pipefail

WG_IF="wg0"
WAN="wlan0"   # upstream: Starlink router Wi-Fi, campground or hotel Wi-Fi
LAN="wlan1"   # private network: the hostapd access point
ENV="/etc/wireguard/travel-vpn.env"

[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }
[[ -f "$ENV" ]] || { echo "$ENV missing. Run travel-vpn-setup.sh first."; exit 1; }
# shellcheck source=/dev/null
source "$ENV"

need_firewall() {
  nft list chain inet filter direct_access > /dev/null 2>&1 \
    || { echo "Kill-switch firewall not loaded. Install travel-vpn/nftables.conf first."; exit 1; }
}

set_pihole_upstream() {
  command -v pihole-FTL > /dev/null || return 0
  pihole-FTL --config dns.upstreams "[\"$1\"]" > /dev/null
  pihole reloaddns > /dev/null 2>&1 || true
  echo "    Pi-hole upstream DNS: $1"
}

handshake_secs() {   # seconds since the last handshake, or empty if none
  local ts
  ts=$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -n | tail -1)
  [[ -n "$ts" && "$ts" != 0 ]] && echo $(( $(date +%s) - ts ))
  return 0
}

handshake_age() {
  local s; s=$(handshake_secs)
  if [[ -z "$s" ]]; then echo "none yet"; else echo "${s}s ago"; fi
}

# ---- security check helpers ----------------------------------------------
pass=0; warn=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
wrn() { printf '  WARN  %s\n' "$1"; warn=$((warn+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

ip2int() { local IFS=.; read -r a b c d <<< "$1"; echo $(( (a<<24) + (b<<16) + (c<<8) + d )); }
cidr_of() { ip -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | head -1; }
overlap() {   # do two CIDRs overlap?
  local a=${1%/*} am=${1#*/} b=${2%/*} bm=${2#*/} m
  m=$(( am < bm ? am : bm ))
  local mask=$(( m == 0 ? 0 : (0xFFFFFFFF << (32 - m)) & 0xFFFFFFFF ))
  (( ($(ip2int "$a") & mask) == ($(ip2int "$b") & mask) ))
}

run_check() {
  echo "Firewall and kill switch"
  if systemctl is-active --quiet nftables; then ok "nftables service is running"; else bad "nftables service is not running"; fi
  if systemctl is-enabled --quiet nftables 2>/dev/null; then ok "firewall loads at boot"; else bad "firewall not enabled at boot: sudo systemctl enable nftables"; fi
  if nft list chain inet filter direct_access > /dev/null 2>&1; then
    if grep -q accept <<< "$(nft list chain inet filter direct_access)"; then
      bad "kill switch OPEN (portal mode): run  sudo travel-vpn on"
    else
      ok "kill switch ON: devices can only use the tunnel"
    fi
  else
    bad "kill-switch chain missing: install travel-vpn/nftables.conf"
  fi
  if grep -q 'policy drop' <<< "$(nft list chain inet filter forward 2>/dev/null)"; then ok "forwarding policy is drop"; else bad "forward chain policy is not drop"; fi
  if grep -q 'policy drop' <<< "$(nft list chain inet filter input 2>/dev/null)"; then ok "nothing on Starlink or the tunnel can connect in"; else bad "input chain policy is not drop"; fi

  echo "Tunnel"
  local s; s=$(handshake_secs)
  if ! systemctl is-active --quiet "wg-quick@$WG_IF"; then
    bad "tunnel is down: sudo travel-vpn on"
  elif [[ -z "$s" ]]; then
    bad "tunnel up but no handshake: Wi-Fi login page, blocked VPN, or bad config"
  elif (( s > 180 )); then
    wrn "last handshake ${s}s ago (should be under 3 minutes)"
  else
    ok "tunnel up, last handshake ${s}s ago"
  fi
  if systemctl is-enabled --quiet "wg-quick@$WG_IF" 2>/dev/null; then ok "tunnel starts at boot"; else wrn "tunnel not enabled at boot"; fi
  if grep -qE '^PersistentKeepalive' "/etc/wireguard/$WG_IF.conf" 2>/dev/null; then ok "keepalive set (needed behind Starlink CGNAT)"; else wrn "no PersistentKeepalive: the tunnel may go quiet behind CGNAT"; fi
  if [[ -f "/etc/systemd/system/wg-quick@$WG_IF.service.d/10-travel.conf" ]]; then ok "tunnel retries automatically"; else wrn "no auto-retry: run harden.sh"; fi

  echo "DNS (Pi-hole)"
  if command -v pihole-FTL > /dev/null; then
    local up; up=$(pihole-FTL --config dns.upstreams 2>/dev/null | tr -d '[] "')
    if [[ "$up" == "$PROVIDER_DNS" ]]; then ok "Pi-hole upstream is the VPN's DNS ($up): lookups stay in the tunnel"
    else wrn "Pi-hole upstream is '$up', expected $PROVIDER_DNS: run  sudo travel-vpn on"; fi
    if grep -qE ':53 .*pihole-FTL' <<< "$(ss -lunp 2>/dev/null)"; then ok "Pi-hole owns port 53"; else bad "Pi-hole is not answering on port 53"; fi
  else
    wrn "Pi-hole not found"
  fi

  echo "Files and accounts"
  if [[ "$(stat -c '%a %U' /etc/wireguard)" == "700 root" ]] \
     && [[ -z "$(find /etc/wireguard -type f ! -perm 600)" ]]; then
    ok "WireGuard keys readable by root only"
  else
    bad "WireGuard files too open: run harden.sh"
  fi
  if command -v sshd > /dev/null; then
    local sshd_t; sshd_t=$(sshd -T 2>/dev/null)
    if grep -q '^permitrootlogin no' <<< "$sshd_t"; then ok "SSH: root login off"; else wrn "SSH: root login allowed"; fi
    if grep -q '^passwordauthentication no' <<< "$sshd_t"; then ok "SSH: keys only"; else wrn "SSH: password logins allowed (fine until you set up a key)"; fi
  fi
  if grep -qs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then ok "automatic security updates on"; else wrn "automatic security updates off: run harden.sh"; fi

  echo "Private Wi-Fi ($LAN)"
  local hc=/etc/hostapd/hostapd.conf
  if [[ -f "$hc" ]]; then
    local km; km=$(grep -oP '^wpa_key_mgmt=\K.*' "$hc" || true)
    if [[ "$km" == *SAE* ]]; then ok "Wi-Fi uses WPA3 ($km)"
    elif [[ "$km" == *WPA-PSK* ]]; then wrn "Wi-Fi uses WPA2 only; WPA3 (SAE) is stronger if your devices support it"
    else bad "Wi-Fi security not recognized (wpa_key_mgmt=$km)"; fi
    local pw; pw=$(grep -oP '^(wpa_passphrase|sae_password)=\K.*' "$hc" | head -1 || true)
    if (( ${#pw} >= 12 )); then ok "Wi-Fi password is ${#pw} characters"; else wrn "Wi-Fi password is under 12 characters"; fi
  else
    wrn "$hc not found; check your hostapd settings by hand"
  fi

  echo "Network layout"
  local w l; w=$(cidr_of "$WAN"); l=$(cidr_of "$LAN")
  if [[ -z "$w" ]]; then wrn "$WAN has no address: connect it to Starlink (nmcli)"
  elif [[ -z "$l" ]]; then bad "$LAN has no address: hostapd/dnsmasq network not up"
  elif overlap "$w" "$l"; then bad "$WAN ($w) and $LAN ($l) overlap: change the private network's subnet"
  else ok "no subnet clash: $WAN $w, $LAN $l"; fi

  echo
  echo "Result: $pass passed, $warn warnings, $fail failed"
  (( fail == 0 ))
}

case "${1:-status}" in
  on)
    need_firewall
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
    need_firewall
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
    need_firewall
    if systemctl is-active --quiet "wg-quick@$WG_IF"; then
      echo "Tunnel:       UP (last handshake $(handshake_age))"
    else
      echo "Tunnel:       DOWN"
    fi
    if grep -q accept <<< "$(nft list chain inet filter direct_access)"; then
      echo "Kill switch:  OPEN (portal mode, devices NOT protected)"
    else
      echo "Kill switch:  ON"
    fi
    echo "Public IPv4:  $(curl -4 -s --max-time 5 https://ifconfig.me || echo 'no answer')"
    ;;

  check)
    run_check
    ;;

  *)
    echo "Usage: sudo travel-vpn on | off | status | check"
    exit 1
    ;;
esac
