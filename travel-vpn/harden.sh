#!/usr/bin/env bash
# harden.sh — security hardening for the RPi travel router.
# Run after travel-vpn-setup.sh:   sudo ./harden.sh
# Safe to re-run. Every change is a separate drop-in file, listed at the end,
# so it is easy to see (and undo) exactly what was changed.
set -euo pipefail

WAN="wlan0"   # upstream: Starlink router Wi-Fi, campground or hotel Wi-Fi
WG_IF="wg0"

[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }
changed=()

# --- 1. Lock down the WireGuard files ------------------------------------
# The config holds your private key: root only.
if [[ -d /etc/wireguard ]]; then
  echo "==> WireGuard files: root only"
  chown -R root:root /etc/wireguard
  chmod 700 /etc/wireguard
  find /etc/wireguard -type f -exec chmod 600 {} +
fi

# --- 2. Start the tunnel only after the firewall, and keep retrying --------
# On a campground or hotel Wi-Fi the tunnel may fail until you log in, or the
# Starlink dish may still be finding satellites at boot. Retry every 30 s forever.
# Requires=nftables means the tunnel never runs without the kill switch loaded.
echo "==> Tunnel: start after the firewall and network, retry on failure"
dropin="/etc/systemd/system/wg-quick@$WG_IF.service.d"
install -d "$dropin"
cat > "$dropin/10-travel.conf" <<'EOF'
[Unit]
Requires=nftables.service
After=nftables.service network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Restart=on-failure
RestartSec=30
EOF
systemctl enable nftables > /dev/null 2>&1 || true
changed+=("$dropin/10-travel.conf")

# --- 3. Kernel network hardening -----------------------------------------
echo "==> Kernel: ignore redirects and source routing, log spoofed packets"
cat > /etc/sysctl.d/98-travel-hardening.conf <<'EOF'
# RPi travel router hardening (harden.sh)
# Don't let other devices on Starlink/campground Wi-Fi re-route our traffic
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
# Log packets with impossible source addresses
net.ipv4.conf.all.log_martians = 1
# Ignore broadcast pings and resist SYN floods
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
EOF
sysctl --system > /dev/null
changed+=("/etc/sysctl.d/98-travel-hardening.conf")

# --- 4. SSH: no root login, keys only (if you have a key) -----------------
# The firewall already blocks SSH from Starlink and the tunnel; this protects
# the private Wi-Fi side too, in case someone learns the Wi-Fi password.
if command -v sshd > /dev/null; then
  echo "==> SSH: no root login, 3 tries per connection"
  key_found=false
  for f in /home/*/.ssh/authorized_keys; do
    [[ -s "$f" ]] && key_found=true
  done
  conf="/etc/ssh/sshd_config.d/10-travel-hardening.conf"
  {
    echo "# RPi travel router hardening (harden.sh)"
    echo "PermitRootLogin no"
    echo "MaxAuthTries 3"
    echo "X11Forwarding no"
    if $key_found; then
      echo "PasswordAuthentication no"
      echo "KbdInteractiveAuthentication no"
    fi
  } > "$conf"
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    changed+=("$conf")
    if $key_found; then
      echo "    Password logins OFF (an SSH key was found). Keep this session open"
      echo "    and test a new SSH login with your key before logging out."
    else
      echo "    No SSH key found, so password logins stay ON. Set up a key with"
      echo "    ssh-copy-id from your computer, then run harden.sh again."
    fi
  else
    rm -f "$conf"
    echo "    sshd rejected the settings; nothing changed."
  fi
fi

# --- 5. Automatic security updates ---------------------------------------
echo "==> Automatic security updates"
apt-get install -y unattended-upgrades > /dev/null
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
changed+=("/etc/apt/apt.conf.d/20auto-upgrades")

# --- 6. Don't announce the Pi on outside networks ------------------------
# Avahi (the ".local" name service) broadcasts the Pi's name on every network.
# Keep it on the private Wi-Fi only, so campground neighbors don't see "rpi5".
avahi="/etc/avahi/avahi-daemon.conf"
if [[ -f "$avahi" ]]; then
  echo "==> Avahi: stay quiet on $WAN and $WG_IF"
  if grep -qE '^#?\s*deny-interfaces=' "$avahi"; then
    sed -i -E "s/^#?\s*deny-interfaces=.*/deny-interfaces=$WAN,$WG_IF/" "$avahi"
  else
    sed -i -E "/^\[server\]/a deny-interfaces=$WAN,$WG_IF" "$avahi"
  fi
  systemctl restart avahi-daemon 2>/dev/null || true
  changed+=("$avahi (deny-interfaces)")
fi

systemctl daemon-reload

echo
echo "Hardening done. Files written or changed:"
printf '    %s\n' "${changed[@]}"
echo
echo "Now run:  sudo travel-vpn check"
