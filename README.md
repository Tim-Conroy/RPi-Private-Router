# RPi-Private-Router
How to build a Raspberry Pi private router.


# Raspberry Pi as a private Wi-Fi router (two Wi-Fi interfaces)

Turn a Raspberry Pi (RPi) with two Wi-Fi radios into a small router. One radio joins your home Wi-Fi. The other broadcasts a new private Wi-Fi network. Devices on the private network reach the internet through the RPi.

> **Tested on:** Raspberry Pi 5, Debian (Trixie), October 25, 2026
>
> **Path B tested:** Successful!

## How it works

This is **routing plus NAT**, not a true Layer 2 (Data Link) bridge. The RPi sits on two separate networks and passes traffic between them:

```
Internet -> Home router -> RPi (wlan1 | wlan0) -> Your devices
            192.168.1.1     192.168.1.50 | 10.10.10.1   10.10.10.x
```

| Who | Job | Network | Example address |
|---|---|---|---|
| Home router | Gives the RPi an address and internet | Home 192.168.1.0/24 | 192.168.1.1 |
| RPi `wlan1` | Joins the home Wi-Fi like a laptop would | Home 192.168.1.0/24 | 192.168.1.50 |
| RPi `wlan0` | Broadcasts the private Wi-Fi network | Private 10.10.10.0/24 | 10.10.10.1 |
| Laptop / phone | Join the RPi's private Wi-Fi | Private 10.10.10.0/24 | 10.10.10.23 / .24 |

All addresses are examples. The home and private ranges must not overlap. If your home network already uses `10.10.10.x`, pick another private range such as `10.20.30.0/24`.

Three jobs make it work:

1. **Access point:** turns one radio into a Wi-Fi network others can join.
2. **DHCP:** hands each device a private address when it joins.
3. **Forwarding and NAT:** passes traffic between the two radios and rewrites the sender address (for example `10.10.10.24` becomes `192.168.1.50`), so the home router accepts it.

## Interface names: check yours first

Linux names the radios in the order it finds them. In this guide `wlan1` is the home Wi-Fi link and `wlan0` is the private network. If your Pi is the other way round, swap the names in every command.

```bash
ip -br link
nmcli device
iw list | grep -A8 "Supported interface modes"
sudo nmcli device show | grep -E "GENERAL.DEVICE|GENERAL.CONNECTION"
```

In the `iw list` output, look for `AP` under the radio you plan to use for the private network. Not every USB Wi-Fi adapter supports AP mode.

## Pick one path

| | Path A: NetworkManager | Path B: Manual |
|---|---|---|
| Idea | One tool does the access point, DHCP and NAT | Three separate tools you configure yourself |
| Steps | Four | More |
| Survives reboot | Yes, saved as a connection | Only if you set it up (see below) |
| Choose it if | You want it working fast | You want to learn it or need custom control |

Follow one path, not both. They compete for the same radio. Not sure? Start with Path A.

---

## Path A: NetworkManager

NetworkManager is the default on current Raspberry Pi OS. With `ipv4.method shared` it runs DHCP and NAT for you.

**Step 1: Check the radios** (see the commands above).

**Step 2: Join the home Wi-Fi on `wlan1`** (skip if already connected):

```bash
sudo nmcli device wifi connect "HomeSSID" \
  password "HomePassword" ifname wlan1
```

**Step 3: Create the private network on `wlan0`:**

```bash
sudo nmcli connection add type wifi \
  ifname wlan0 con-name RPiPrivate \
  ssid RPiPrivate \
  802-11-wireless.mode ap \
  802-11-wireless.band bg \
  ipv4.method shared \
  ipv4.addresses 10.10.10.1/24 \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "ChooseAStrongPassphrase"
sudo nmcli connection up RPiPrivate
```

**Step 4: Verify:**

```bash
ip -br addr
ip route
cat /proc/sys/net/ipv4/ip_forward
sudo nft list ruleset | grep -i masq
```

Expect `wlan1` on `192.168.1.x`, `wlan0` on `10.10.10.1`, and a `1` from `ip_forward`. Join `RPiPrivate` from a phone to test. On some setups the `grep -i masq` prints nothing even when sharing works. If the phone has internet, it is fine.

**Survive a reboot:** the connection is saved. Confirm autoconnect is on:

```bash
nmcli -f NAME,AUTOCONNECT connection show
sudo nmcli connection modify RPiPrivate connection.autoconnect yes
```

**Undo:**

```bash
sudo nmcli connection delete RPiPrivate
```

---

## Path B: Manual setup (hostapd, dnsmasq, nftables)

**Step 1: Install the tools and address `wlan0`:**

```bash
sudo apt install hostapd dnsmasq nftables
sudo nmcli device set wlan0 managed no
sudo ip addr add 10.10.10.1/24 dev wlan0
sudo ip link set wlan0 up
```

**Step 2: Access point.** Create `/etc/hostapd/hostapd.conf`:

```ini
interface=wlan0
driver=nl80211
ssid=RPiPrivate
country_code=US
hw_mode=g
channel=6
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=YourPassphrase
```

Use your own country code, and a passphrase of 8 to 63 characters. On Raspberry Pi OS Trixie, `/etc/default/hostapd` has `DAEMON_CONF` commented out, and without it the service starts hostapd with no config file and fails with status 1. Point it at your file, then start hostapd:

```bash
sudo sed -i 's|^#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
grep -n "^DAEMON_CONF" /etc/default/hostapd
sudo systemctl unmask hostapd
sudo systemctl daemon-reload
sudo systemctl enable --now hostapd
```

If hostapd will not start, run it in the foreground. The real error prints to the terminal (press `Ctrl+C` to stop it):

```bash
sudo systemctl stop hostapd
sudo hostapd -d /etc/hostapd/hostapd.conf
```

Typos in `hostapd.conf` are the most common cause. Check these lines exactly:

- `driver=nl80211` (a lowercase L, not the digit 1)
- `wpa_key_mgmt=WPA-PSK`
- `wpa_passphrase=...` with no quotes, 8 to 63 characters

A healthy start ends with `wlan0: AP-ENABLED`.

**Step 3: DHCP.** Create `/etc/dnsmasq.d/private.conf`. Each setting must be on one line:

```ini
interface=wlan0
dhcp-range=10.10.10.20,10.10.10.100,255.255.255.0,12h
```

```bash
sudo systemctl restart dnsmasq
```

**If Pi-hole runs on the same Pi:** Pi-hole's FTL engine is a fork of dnsmasq and already owns port 53, so a separate dnsmasq fails with `failed to create listening socket for port 53: Address already in use`. Make dnsmasq DHCP-only and let Pi-hole answer DNS on the private network:

```ini
interface=wlan0
dhcp-range=10.10.10.20,10.10.10.100,255.255.255.0,12h
port=0
dhcp-option=option:router,10.10.10.1
dhcp-option=option:dns-server,10.10.10.1
```

`port=0` turns off dnsmasq's DNS function. Check that Pi-hole accepts queries from the private subnet (the default `LOCAL` mode does):

```bash
sudo pihole-FTL --config dns.listeningMode
```

**Testing dnsmasq:** the Debian service starts dnsmasq through a helper that also reads `/etc/dnsmasq.d/`. A manual `dnsmasq --test` or `dnsmasq -d` does not behave the same way, and `dnsmasq -d` fails with `Address already in use` while the service is running. Check the config the way the service does:

```bash
sudo /usr/share/dnsmasq/systemd-helper checkconfig
```

No output means the config is valid.

**Step 4: Forwarding:**

```bash
echo "net.ipv4.ip_forward=1" | \
  sudo tee /etc/sysctl.d/90-router.conf
sudo sysctl --system
```

**Step 5: NAT with nftables:**

```bash
sudo nft add table ip nat
sudo nft add chain ip nat postrouting \
  '{ type nat hook postrouting priority 100 ; }'
sudo nft add rule ip nat postrouting \
  oifname "wlan1" masquerade
sudo systemctl enable nftables
```

If `sudo nft list ruleset` already shows an empty `table ip nat`, skip the `add table` command and add only the chain and the rule.

Save the rules so they survive a reboot. This overwrites the file, and the leading `flush ruleset` stops duplicate rules from loading twice:

```bash
sudo sh -c 'echo "flush ruleset" > /etc/nftables.conf; nft list ruleset >> /etc/nftables.conf'
sudo systemctl enable nftables
```

### Make Path B survive a reboot

Two settings from Step 1 are lost at reboot: `managed no` and the `ip addr` address. Without them NetworkManager takes `wlan0` back, and phones that join get a `169.254.x.x` address because dnsmasq has no address to serve from.

Keep NetworkManager away from `wlan0`:

```bash
sudo tee /etc/NetworkManager/conf.d/unmanaged-wlan0.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
sudo systemctl restart NetworkManager
sudo systemctl restart hostapd
```

Keep the address with systemd-networkd. On Trixie it is installed but disabled by default, so enable it:

```bash
systemctl list-unit-files | grep systemd-networkd
sudo tee /etc/systemd/network/10-wlan0.network <<'EOF'
[Match]
Name=wlan0

[Network]
Address=10.10.10.1/24
ConfigureWithoutCarrier=yes
EOF
sudo systemctl enable --now systemd-networkd
sudo systemctl restart dnsmasq
```

Paste the file blocks without indentation, or the closing `EOF` will not end the input. If dnsmasq still starts before the address exists after a reboot, add `bind-dynamic` to `/etc/dnsmasq.d/private.conf`.

### Check it after a reboot

```bash
ip -br addr show wlan0
sudo nft list table ip nat
iw dev wlan0 info
cat /proc/sys/net/ipv4/ip_forward
cat /var/lib/misc/dnsmasq.leases
```

Expect `10.10.10.1/24` on `wlan0`, the `oifname "wlan1" masquerade` rule, `type AP` with your SSID, a `1` from `ip_forward`, and your phone listed in the leases after it joins.
---

## Troubleshooting

| Symptom | What to check |
|---|---|
| Both networks use `10.10.10.x` | Change the private range, for example `10.20.30.0/24` |
| Access point will not start | The radio you chose may not support AP mode. Run the `iw list` check |
| hostapd refuses to run | Set a Wi-Fi `country_code` |
| Devices join but have no internet | Check `ip_forward` is `1` and the masquerade rule exists |
| hostapd exits with status 1 and keeps restarting | `DAEMON_CONF` is commented out in `/etc/default/hostapd`, or `hostapd.conf` has a typo. Run `sudo hostapd -d /etc/hostapd/hostapd.conf` |
| dnsmasq: `port 53 ... Address already in use` | Pi-hole is using port 53. Add `port=0` to `/etc/dnsmasq.d/private.conf` |
| Phone shows a `169.254.x.x` address | `wlan0` has no `10.10.10.1/24`. Check `ip -br addr show wlan0` and the systemd-networkd file |
| Phone shows "No Internet Connection" | Check the masquerade rule, `ip_forward`, and `nslookup example.com 10.10.10.1`. Toggle the phone's Wi-Fi after fixing |
| SSID disappears after a reboot | NetworkManager took `wlan0` back. Add the `unmanaged-wlan0.conf` file |

## Notes

- Devices on the private network are hidden from outside traffic, but they can still reach devices on your home network (for example a printer) unless you add firewall rules.
- Change every placeholder (`HomeSSID`, `HomePassword`, `ChooseAStrongPassphrase`, `YourPassphrase`) before use.
