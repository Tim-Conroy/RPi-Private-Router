# Slide show: Starlink + RPi Secure Travel Router

The slides for the "connect to Starlink" part of the video, written out one slide per section: what's on screen and the exact commands. Use it to follow along, or to rebuild the slides in your own tool.

The full build steps are in the [travel VPN guide](README.md); this file follows its step 1 and the checks after it.

> **Names used on the slides are examples.** "Starlink WiFi" stands in for your Starlink network name (SSID), "TrailRig Starlink" for your subscription nickname, and "ASUS" for your home Wi-Fi. Use your own names when you run the commands.

**Slides**

1. [Cover](#1-cover)
2. [How the pieces connect](#2-how-the-pieces-connect)
3. [Starlink uses CGNAT](#3-starlink-uses-cgnat-carrier-grade-nat)
4. [Two names in the Starlink app](#4-two-names-in-the-starlink-app)
5. [Step 1: Have the Pi scan for Starlink](#5-step-1-have-the-pi-scan-for-starlink)
6. [Step 2: Save the Starlink profile](#6-step-2-save-the-starlink-profile)
7. [Step 3: Connect and confirm](#7-step-3-connect-and-confirm)
8. [Which Wi-Fi does the Pi pick?](#8-which-wi-fi-does-the-pi-pick)
9. [Step 4: Check the tunnel](#9-step-4-check-the-tunnel)
10. [If something goes wrong](#10-if-something-goes-wrong)
11. [Recap](#11-recap)

---

## 1. Cover

**STARLINK + RPi**
**Secure Travel Router**

Raspberry Pi 5 | WireGuard | Proton VPN Plus | Pi-hole

Graphic: a shield with a Wi-Fi symbol and padlock, linked to a café, an airport, a hotel and an RV, showing that the router protects you wherever you connect.

Flow along the bottom: **iPhone · MacBook → Raspberry Pi 5 → Starlink → Proton VPN**

---

## 2. How the pieces connect

Data flows top to bottom:

| | Piece | Role |
|---|---|---|
| ↓ | **iPhone and MacBook** | Join the private Wi-Fi "RPI-PROTO-WIFI" |
| ↓ | **Raspberry Pi 5** | Pi-hole + kill switch · private Wi-Fi on `wlan1` |
| ↓ | **Starlink Mini** | Wi-Fi "Starlink WiFi" · the Pi joins it on `wlan0` |
| ↓ | **Proton VPN** | Unlocks the tunnel at a server near you |
| | **Internet** | Websites see Proton's address, not yours |

**Encrypted WireGuard tunnel** (spans the Pi, Starlink and Proton): Everything from the Pi to Proton's server is scrambled. Starlink and anyone nearby can't read it.

---

## 3. Starlink uses CGNAT (Carrier-Grade NAT)

**Starlink customers → One shared public address → Internet**: all share one address to the internet.

| Connecting out: works ✓ | Connecting in: blocked ✗ |
|---|---|
| Browsing, streaming, and the Pi's tunnel to Proton all start from your side. | Nothing on the internet can reach your Pi: no port forwarding, no VPN server on the Pi. |

So the Pi builds the tunnel from your side, and sends a keepalive every 25 seconds so CGNAT doesn't forget it.

**Where the sharing happens:** not on the dish or the satellite, but at Starlink's ground network (its point of presence, or PoP). The Mini's router gives the Pi a private `192.168.1.x` address, the dish gets a carrier address from `100.64.x.x`, and CGNAT equipment at the PoP swaps those for a shared public address on the way out.

---

## 4. Two names in the Starlink app

| Top left of the app | Next to the Wi-Fi icon |
|---|---|
| **TrailRig Starlink** · Mini | **Starlink WiFi** · 0 devices |
| **Subscription nickname** | **Wi-Fi network name (SSID)** |
| Labels your dish in your account. The Pi never uses it. | The network the Pi joins. Its password is in the app's Wi-Fi settings. |
| ✗ Not this one | ✓ Use this one |

---

## 5. Step 1: Have the Pi scan for Starlink

On a laptop terminal, connect to the RPi over SSH and run the commands below. The Pi searches with its own Wi-Fi; your phone and laptop never join Starlink directly.

```bash
# scan with the built-in Wi-Fi
sudo nmcli dev wifi rescan ifname wlan0
nmcli dev wifi list ifname wlan0
```

Example output:

```
SSID           SIGNAL  SECURITY
Starlink WiFi  82      WPA2
ASUS           64      WPA2
--             40      WPA2
```

- Look for **Starlink WiFi**, the name next to the Wi-Fi icon in the app.
- Rescan needs **sudo**, or you get "not authorized".
- Ignore **--** rows: those are hidden networks.

---

## 6. Step 2: Save the Starlink profile

```bash
# type the password; it won't show
read -rsp "Starlink password: " PSK; echo
```

**One command · copy all 7 lines:**

```bash
sudo nmcli con add type wifi \
  ifname wlan0 con-name STARLINK \
  ssid "Starlink WiFi" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "$PSK" \
  connection.autoconnect yes \
  connection.autoconnect-priority 10
```

```bash
unset PSK
```

- `read -rsp` keeps the password off the screen and out of history.
- `key-mgmt wpa-psk` must be set, or nmcli refuses the profile.
- **Priority 10** means Starlink wins over home Wi-Fi when both are in range.

---

## 7. Step 3: Connect and confirm

```bash
sudo nmcli con up STARLINK

# which network is wlan0 on?
iw dev wlan0 info | grep ssid
#   ssid Starlink WiFi

# did Starlink give an address?
ip -br a show wlan0
# wlan0  UP  192.168.1.x/24
```

In the Starlink app: **Starlink WiFi · 1 device**. Going from 0 to 1 device means the Pi is on Starlink.

---

## 8. Which Wi-Fi does the Pi pick?

**Raspberry Pi 5**: `wlan0` joins the highest-priority network it can see.

| Network | When | Priority |
|---|---|---|
| **Starlink WiFi** | On the road | **10** |
| **ASUS (home)** | When Starlink is off | 0 |

Both in range? The Pi joins Starlink. Only home in range? It falls back to ASUS. The VPN runs the same either way.

💡 Already on ASUS when Starlink powers up? The Pi won't switch on its own. Run this, or reboot the Pi:

```bash
sudo nmcli con up STARLINK
```

---

## 9. Step 4: Check the tunnel

```bash
sudo travel-vpn status
sudo travel-vpn check
```

| Tunnel UP | Kill switch ON | Proton IP |
|---|---|---|
| Shown by `sudo travel-vpn status` | Set in `/etc/nftables.conf` on the RPi | Check on your phone: whatismyipaddress.com |
| `wg0` has had a recent handshake with Proton's server | If the tunnel drops, traffic stops instead of leaking | The public address is Proton's, not Starlink's |

What `sudo travel-vpn status` prints (your numbers will differ):

```
Tunnel:       UP (last handshake 12s ago)
Kill switch:  ON
Public IPv4:  <a Proton address>
```

**How the kill switch works:** in [`nftables.conf`](nftables.conf), the `forward` chain has `policy drop`. The only open path for your devices is `wlan1 → wg0` (into the tunnel). Traffic trying to go straight out `wlan1 → wlan0` jumps to the `direct_access` chain, which is empty, so it's dropped. If the tunnel goes down, your devices lose internet instead of leaking over Starlink. `sudo travel-vpn off` adds one `accept` to that chain for captive-portal logins; `sudo travel-vpn on` (or a reboot) empties it again.

**About the public address:** it's the address websites see your traffic coming from. With the tunnel up, that's Proton's exit address, which is often different from the server address in your WireGuard config. That's normal; what matters is that it isn't your Starlink address.

---

## 10. If something goes wrong

| What you see | Fix |
|---|---|
| Rescan says "not authorized" | Run it with `sudo` |
| "key-mgmt: property is missing" | Use `nmcli con add` with `wifi-sec.key-mgmt wpa-psk` |
| Several STARLINK profiles | Delete them all, then add one fresh profile |
| SSH from the Mac hangs | Mac is on home Wi-Fi: turn off Auto-Join for ASUS |
| "Host key changed" warning | Run `ssh-keygen -R` with the Pi's address |
| Pi joined the wrong network | Check priority: STARLINK 10, ASUS 0 |

---

## 11. Recap

**Starlink now sees only encrypted traffic**

1. Find Starlink WiFi
2. Save at priority 10
3. Connect: 1 device
4. Check the tunnel
