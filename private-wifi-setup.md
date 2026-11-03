# Private Wi-Fi: turn the Alfa adapter (`wlan1`) into your travel router's access point

This guide adds the private Wi-Fi that your iPhone, MacBook and other devices join. It uses **hostapd** for the access point and **Pi-hole's built-in DHCP server** to hand out addresses, so there is no separate dnsmasq to install (Pi-hole already contains dnsmasq, and a second copy would fight it for port 53).

**Do this after** the [Wi-Fi access point capability check](wifi-ap-capability-check.md) and [installing Pi-hole](Pi-hole-Installation-Guide.md), and **before** the [travel VPN](travel-vpn/README.md).

| Setting | Value used in this guide |
|---|---|
| Upstream Wi-Fi | `wlan0`, the Pi's built-in Wi-Fi (home Wi-Fi now, Starlink on the road) |
| Private Wi-Fi | `wlan1`, the Alfa USB adapter |
| Private network | `192.168.50.0/24`, Pi = `192.168.50.1` (avoids Starlink's `192.168.1.x`) |
| Addresses for devices | `192.168.50.10` to `192.168.50.200`, from Pi-hole |

All of this can be done over SSH from your home Wi-Fi: nothing here touches `wlan0`.

---

## 0. Check what you have

```bash
dpkg -l hostapd | grep ^ii        # no output = hostapd not installed yet
iw dev                            # wlan0 and wlan1 should both be listed
nmcli dev status                  # who manages each interface
cat /sys/class/net/wlan1/address  # the Alfa's hardware (MAC) address, needed in step 2
```

In `iw dev`, the built-in Wi-Fi's address starts with the Raspberry Pi prefix (`2c:cf:67`, `d8:3a:dd` or `e4:5f:01`), and Alfa adapters usually start with `00:c0:ca`. If they're swapped (Alfa = `wlan0`), stop and fix the names first.

## 1. Install hostapd

```bash
sudo apt update
sudo apt install -y hostapd
```

## 2. Tell NetworkManager to leave the Alfa alone

Replace `<alfa-mac>` with the address from step 0:

```bash
sudo tee /etc/NetworkManager/conf.d/99-unmanaged-alfa.conf > /dev/null <<'EOF'
[keyfile]
unmanaged-devices=mac:<alfa-mac>
EOF
sudo systemctl reload NetworkManager
nmcli dev status | grep wlan1      # should say "unmanaged"
```

## 3. Create the private Wi-Fi

Pick a network name (no spaces is simplest) and a password of **12 to 63 characters**:

```bash
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<'EOF'
interface=wlan1
driver=nl80211
country_code=US
ssid=YOUR-TRAVEL-WIFI
hw_mode=g
channel=6
ieee80211n=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=YOUR-12+-CHARACTER-PASSWORD
EOF
sudo chmod 600 /etc/hostapd/hostapd.conf
```

- Change `country_code` to your country's two-letter code.
- 2.4 GHz channel 6 with WPA2 is the setting most likely to work first time with Realtek adapters such as the 8812AU/8821AU. Your upstream link is often on 5 GHz, so the two don't interfere.
- The password is everything after `wpa_passphrase=`: no quotes, no spaces around `=`.

## 4. Give `wlan1` its address whenever hostapd starts

```bash
sudo mkdir -p /etc/systemd/system/hostapd.service.d
sudo tee /etc/systemd/system/hostapd.service.d/10-wlan1-address.conf > /dev/null <<'EOF'
[Unit]
After=NetworkManager.service

[Service]
ExecStartPost=/usr/sbin/ip addr replace 192.168.50.1/24 dev wlan1
EOF
sudo systemctl daemon-reload
```

## 5. Start the access point

```bash
sudo systemctl unmask hostapd
sudo systemctl enable --now hostapd
systemctl status hostapd --no-pager | head -5
iw dev wlan1 info | grep -E 'type|ssid'
ip -br a show wlan1
```

✅ **You should see:** hostapd `active (running)`, `type AP` with your network name, and `wlan1` `UP` with `192.168.50.1/24`.

## 6. Turn on Pi-hole's DHCP for the private Wi-Fi

```bash
sudo pihole-FTL --config dns.listeningMode       # should be LOCAL (or ALL)
sudo pihole-FTL --config dhcp.start 192.168.50.10
sudo pihole-FTL --config dhcp.end 192.168.50.200
sudo pihole-FTL --config dhcp.router 192.168.50.1
sudo pihole-FTL --config dhcp.netmask 255.255.255.0
sudo pihole-FTL --config dhcp.active true
```

If the listening mode says `SINGLE`, run `sudo pihole-FTL --config dns.listeningMode LOCAL` so Pi-hole answers devices on `wlan1` too.

Pi-hole only hands out addresses on the `192.168.50.x` network, so it never interferes with your home Wi-Fi or Starlink.

## 7. Test

1. **iPhone:** join your network, then Settings → Wi-Fi → ⓘ: the IP address is `192.168.50.x` and the router is `192.168.50.1`.
2. **On the Pi:**
   ```bash
   sudo iw dev wlan1 station dump | grep -E 'Station|signal:'   # the connected device and its signal
   cat /etc/pihole/dhcp.leases                                  # the address Pi-hole gave it
   ```
3. **Safari on the iPhone:** `http://192.168.50.1/admin` opens the Pi-hole dashboard, and the Query Log shows the iPhone's lookups.

Websites won't load yet: that's expected. Internet through the VPN comes with the [travel VPN](travel-vpn/README.md) kill-switch firewall.

## 8. SSH in through the private Wi-Fi

The travel VPN firewall only allows SSH from the private Wi-Fi, so get used to connecting this way:

1. Join the MacBook to your **private Wi-Fi** (not your home or Starlink network; the Mac has no internet here until the travel VPN is set up).
2. Connect:
   ```bash
   ssh <your_username>@192.168.50.1
   ```
3. Answer `yes` to the new host key question.

**"REMOTE HOST IDENTIFICATION HAS CHANGED"?** Your Mac remembers a different Pi (for example another microSD card) at that address. Clear it on the Mac, then connect again:

```bash
ssh-keygen -R 192.168.50.1
```

Keep this guide open on your phone over cellular data while the Mac is offline.

## Optional: WPA3

Once WPA2 works, try WPA3 mixed mode in `/etc/hostapd/hostapd.conf` (needs driver support for SAE):

```ini
wpa_key_mgmt=WPA-PSK SAE
ieee80211w=1
```

Then `sudo systemctl restart hostapd`. If hostapd fails to start, your adapter's driver doesn't support WPA3 as an access point: put back `wpa_key_mgmt=WPA-PSK`, remove the `ieee80211w` line, and restart.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `wlan1` shows `DOWN` and `type managed` | hostapd not installed or not running | Steps 1 and 5 |
| `Unit hostapd.service could not be found` | hostapd not installed | Step 1 |
| hostapd `masked` | Debian ships it masked | `sudo systemctl unmask hostapd` |
| iPhone says wrong password | Typo, placeholder left in, or old password remembered | `sudo grep -E '^(ssid\|wpa_passphrase)=' /etc/hostapd/hostapd.conf` on the Pi; on the iPhone, **Forget This Network** and rejoin |
| iPhone gets a `169.254.x.x` address | Pi-hole DHCP off | Step 6 |
| SSH to `192.168.50.1` hangs at "Connecting" | The Mac is on your home or Starlink Wi-Fi | Join the private Wi-Fi |
| Why hostapd failed | | `journalctl -u hostapd -b --no-pager \| tail -20` |
