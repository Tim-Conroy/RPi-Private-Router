# Travel router startup checklist

Run this after every power-up, top to bottom. It assumes the defaults from the [private Wi-Fi guide](../private-wifi-setup.md) and this folder's [README](README.md): private Wi-Fi on `wlan1` at `192.168.50.1`, Proton VPN on `wg0`.

## 1. Connect

Wait about 2 minutes after power-up, then reach the Pi through its private Wi-Fi (the firewall blocks SSH from your home or Starlink network).

- [ ] MacBook joined to **your private Wi-Fi** (not your home or Starlink Wi-Fi)
- [ ] SSH in:

```bash
ssh <your_username>@192.168.50.1
```

Host key warning after a microSD card swap? On the Mac: `ssh-keygen -R 192.168.50.1`, then connect again and answer `yes`.

SSH hangs at "Connecting"? The Mac has switched back to your home Wi-Fi (common right after a Pi reboot). Rejoin the private Wi-Fi. To stop it switching during setup: System Settings → Wi-Fi → **Details** next to your home network → turn off **Auto-Join** (turn it back on when you're done).

## 2. Quick check (most days, this is all you need)

```bash
sudo travel-vpn status
sudo travel-vpn check
```

- [ ] `status`: **Tunnel UP** with a handshake under 3 minutes, **Kill switch ON**, public IP is your VPN's
- [ ] `check`: no **FAIL** lines (WARN lines for SSH or updates are fine until you run `harden.sh`)

All good? You're done. Anything wrong? Use section 3 to find which piece is down.

## 3. Full checklist

**A. Upstream Wi-Fi (`wlan0`: home Wi-Fi or Starlink)**

```bash
nmcli dev status | grep wlan
```

- [ ] `wlan0` connected to your upstream network; `wlan1` **unmanaged**

**B. Private Wi-Fi (`wlan1`, hostapd)**

```bash
systemctl is-active hostapd
iw dev wlan1 info | grep -E 'type|ssid'
ip -br a show wlan1
```

- [ ] `active`, `type AP`, your network name, address `192.168.50.1/24`

**C. Firewall and kill switch (nftables)**

```bash
systemctl is-active nftables
sudo nft list chain inet filter direct_access
```

- [ ] `active`; the `direct_access` chain is **empty** (empty = kill switch ON)

**D. VPN tunnel (WireGuard `wg0`)**

```bash
sudo wg show | grep -E 'endpoint|latest handshake'
curl -4 -s https://ifconfig.me; echo
```

- [ ] Endpoint is your VPN server (`<server-ip>:51820`), handshake under 3 minutes, and a VPN IPv4 address

**E. Pi-hole**

```bash
sudo pihole status
sudo pihole-FTL --config dns.upstreams
cat /etc/pihole/dhcp.leases
```

- [ ] Blocking enabled; upstream is your VPN's DNS (Proton: `[ "10.2.0.1" ]`); your devices listed with `192.168.50.x` leases

**F. Services start at boot**

```bash
systemctl is-enabled hostapd nftables wg-quick@wg0 pihole-FTL
```

- [ ] Four lines, all `enabled`

**G. Your devices (iPhone cellular data off, VPN apps off)**

- [ ] iPhone or Mac: `https://ifconfig.me` shows the VPN's address, not your home or Starlink one
- [ ] An ad-heavy site loads with ads blocked
- [ ] Mac Terminal: `dig +short doubleclick.net` returns `0.0.0.0`

## 4. Kill switch

**Test it** (devices should lose internet instead of leaking out unprotected):

```bash
sudo systemctl stop wg-quick@wg0     # iPhone and Mac lose internet
sudo travel-vpn on                   # tunnel back, kill switch ON, internet returns
```

**Portal mode** for a campground or hotel Wi-Fi login page:

```bash
sudo travel-vpn off     # NOT protected: log in at http://neverssl.com
sudo travel-vpn on      # back to protected right after
```

- [ ] After any test, `sudo travel-vpn status` shows **Kill switch: ON**

A reboot always turns the kill switch back on.

## 5. Quick fixes

| What's down | Fix | Then check |
|---|---|---|
| Private Wi-Fi (hostapd) | `sudo systemctl restart hostapd` | `ip -br a show wlan1` |
| VPN tunnel | `sudo travel-vpn on` | `sudo travel-vpn status` |
| Firewall | `sudo nft -c -f /etc/nftables.conf && sudo systemctl restart nftables && sudo travel-vpn on` | `sudo travel-vpn check` |
| Pi-hole | `sudo systemctl restart pihole-FTL` | `sudo pihole status` |
| Upstream Wi-Fi | `nmcli dev wifi list ifname wlan0`, then `sudo nmcli con up "<network name>"` | `nmcli dev status` |

Still stuck? See why a service failed with `journalctl -u <service> -b --no-pager | tail -20` (for example `hostapd`, `wg-quick@wg0`, `nftables`, `pihole-FTL`).

## 6. Shut down and restart safely

Always shut down properly before pulling the power, to protect the microSD card.

```bash
sudo shutdown -h now     # power off
sudo reboot              # restart instead
```

- [ ] Wait until the green activity light stops blinking (about 10 seconds) before unplugging
- [ ] After power-up, wait about 2 minutes, then start again at section 1

Everything (hostapd, firewall, VPN tunnel, Pi-hole) starts on its own at boot, with the kill switch ON.

## 7. NVMe boot and backup router

If your router runs from an NVMe drive (see the [NVMe boot and backup guide](../nvme-boot-and-backup.md)), the microSD card is the spare copy.

**Check which drive it booted from:**

```bash
findmnt /                                  # /dev/nvme0n1p2 = NVMe (normal)
sudo rpi-eeprom-config | grep BOOT_ORDER   # 0xf416 = NVMe, then microSD, then USB
```

- [ ] `findmnt /` shows `nvme0n1p2` (if it shows `mmcblk0p2`, set the boot order: `sudo rpi-eeprom-config --edit`, `BOOT_ORDER=0xf416`, reboot)

**Keep the microSD spare up to date** (after any change, and about once a month):

```bash
sudo rpi-clone mmcblk0      # only works while booted from the NVMe
```

**Using the backup Raspberry Pi 5** (only if the main one fails):

- [ ] Shut down the main Pi first: **never run both at once** (same Wi-Fi, same address, same VPN key)
- [ ] Move the microSD card (and the Alfa adapter, if sharing one) to the backup Pi and power it on
- [ ] Using a different Alfa? Its address must be listed in `/etc/NetworkManager/conf.d/99-unmanaged-alfa.conf` (`unmanaged-devices=mac:<main-alfa>;mac:<backup-alfa>`)
- [ ] Run this checklist from section 1
