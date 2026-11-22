# Hotel and Venue Wi-Fi

Join the Raspberry Pi 5 travel router to a hotel, café or campground Wi-Fi network. The venue's Wi-Fi becomes the Pi's upstream internet on `wlan0`. Your private Wi-Fi on `wlan1`, the WireGuard tunnel, the kill switch and Pi-hole don't change.

> Part of the [RPi Private Router](../README.md) project. Set up the [Travel VPN](../travel-vpn/README.md) first. Joining Starlink instead? See [Connecting to Starlink](../connect-to-starlink/README.md).

Every command on this page runs **on the Pi**: over SSH from a device on your private Wi-Fi, or with a keyboard and monitor plugged into the Pi. Joining a new network on `wlan0` won't drop an SSH session on the private Wi-Fi.

## Contents

1. [What nmcli means](#what-nmcli-means)
2. [Find the venue's network](#1-find-the-venues-network)
3. [Pick the right network](#2-pick-the-right-network)
4. [Password or sign-in page?](#3-password-or-sign-in-page)
5. [Save the profile: open Wi-Fi](#4a-save-the-profile-open-wi-fi)
6. [Save the profile: Wi-Fi with a password](#4b-save-the-profile-wi-fi-with-a-password)
7. [Connect and check](#5-connect-and-check)
8. [Get through a sign-in page](#6-get-through-a-sign-in-page)
9. [Where the profile and its UUID are saved](#where-the-profile-and-its-uuid-are-saved)
10. [Troubleshooting](#troubleshooting)

## What nmcli means

**nmcli** is short for **NetworkManager Command-Line Interface**.

- **nm** is NetworkManager, the service running in the background on the Pi that manages every network connection.
- **cli** means command-line interface: you control it by typing commands instead of clicking menus.

nmcli is the typed version of the Wi-Fi menu on a desktop. If you'd rather use the arrow keys, `sudo nmtui` opens a simple menu screen inside the terminal.

Every nmcli command follows the same pattern: `sudo` if the command needs it, then `nmcli`, then what you want it to do. Leaving out `nmcli` gives `sudo: dev: command not found`.

## 1. Find the venue's network

```bash
sudo nmcli dev wifi rescan ifname wlan0
nmcli dev wifi list ifname wlan0
```

- `rescan` tells the built-in radio to look for networks. It needs `sudo`, or you get `not authorized`.
- `list` shows what it found. It works without `sudo`, and still works if the rescan was refused.
- The list opens in a scrolling viewer. Press `q` to leave it.

For a shorter list with only the columns that matter:

```bash
nmcli -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list ifname wlan0
```

| Column | What it tells you |
|---|---|
| `IN-USE` | A `*` marks the network the Pi is on right now |
| `SSID` | The Wi-Fi network name. Copy it exactly: it's case-sensitive |
| `SIGNAL` | Higher is stronger |
| `SECURITY` | `WPA2` or `WPA3` means a password. `--` means open Wi-Fi |

Not listed? Move closer, wait a minute, then rescan.

## 2. Pick the right network

A hotel scan can list a dozen networks. Cross them off in this order:

| What you see | What to do |
|---|---|
| Your own private Wi-Fi name | **Skip, and never join it from the Pi.** The Pi's built-in radio can hear your Alfa adapter's network too. If `wlan0` joins it, NetworkManager saves it and can rejoin it on its own later, leaving your devices with no internet ([why](../router-connected-to-itself/README.md)) |
| A name like `Hotel_Admin` or `Staff` with `WPA2` | **Skip.** Staff network |
| `WPA2 802.1X` under SECURITY | **Skip.** Enterprise login with a username or certificate, often used by a hotel app's auto sign-in. Not a simple password |
| `--` as the name | **Skip.** Hidden network |
| A guest name with `--` under SECURITY | **Pick.** Open guest Wi-Fi, which usually shows a sign-in page |

- If two guest names are left, the Wi-Fi card from the front desk tells you which one to use.
- **The same name listed several times is normal.** The venue has several access points on different channels (1, 6 and 11 are 2.4 GHz; 36 and up are 5 GHz). You only type the **name**; NetworkManager picks the best access point on its own.

## 3. Password or sign-in page?

They are different things, and some hotels have both.

| The venue gives you | It means | Go to |
|---|---|---|
| A **password to join** the network | WPA2 or WPA3 security | [4b](#4b-save-the-profile-wi-fi-with-a-password), then [5](#5-connect-and-check) |
| An open network, then a **page asking for your room number or last name** | A captive portal | [4a](#4a-save-the-profile-open-wi-fi), [5](#5-connect-and-check), then [6](#6-get-through-a-sign-in-page) |

## 4a. Save the profile: open Wi-Fi

```bash
sudo nmcli con add type wifi \
  ifname wlan0 con-name VENUE \
  ssid "<Your_Venue_SSID>"
```

This is **one command over three lines**. The `\` at the end of a line tells the shell to keep reading on the next line, so copy and paste all three together.

| Part | What it does |
|---|---|
| `sudo` | Saving a system-wide profile needs root |
| `nmcli con add` | Create a new connection profile |
| `type wifi` | A Wi-Fi profile, not Ethernet or a VPN |
| `ifname wlan0` | Use the Pi's built-in radio only, so it never touches `wlan1`, your private Wi-Fi |
| `con-name VENUE` | The **profile name**. `VENUE` is a name **you** choose, such as `HOTEL` or `CAFE`: short, no spaces |
| `ssid "<Your_Venue_SSID>"` | The venue's real Wi-Fi network name, from step 1. Replace the placeholder and don't type the `< >` |

NetworkManager fills in the rest for you:

- **Autoconnect: yes.** The Pi can join it by itself when it's in range and `wlan0` is free.
- **Priority: 0.** The same as home Wi-Fi, so Starlink at priority 10 still wins when it's on.
- **Address: DHCP.** The venue's router hands the Pi an address.
- **No password.** Fine for open Wi-Fi. For a password network, use 4b instead.

The command only **saves** the profile. Step 5 connects.

### Profile name vs. Wi-Fi name

| Setting | What it is | Used for |
|---|---|---|
| `con-name VENUE` | The **profile name**. You choose it | `nmcli con up`, `down`, `modify`, `delete` |
| `ssid "..."` | The **Wi-Fi network name**. The venue sets it | Which network the profile joins |

`unknown connection` means you typed the Wi-Fi name where nmcli wanted the profile name.

## 4b. Save the profile: Wi-Fi with a password

```bash
read -rsp "Venue Wi-Fi password: " PSK; echo

sudo nmcli con add type wifi \
  ifname wlan0 con-name VENUE \
  ssid "<Your_Venue_SSID>" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "$PSK"

unset PSK
```

1. **`read`** asks for the password and holds it in `$PSK` for a moment.

   | Part | Meaning |
   |---|---|
   | `-r` | Keep characters like `\` exactly as typed |
   | `-s` | Silent: the password doesn't show on screen, which is good for filming |
   | `-p "..."` | The prompt you see |
   | `PSK` | The variable that holds it (pre-shared key, the Wi-Fi password) |
   | `; echo` | Move to a new line, since `-s` hides your Enter key |

2. **`nmcli con add`** saves the profile with the password. `wifi-sec.key-mgmt wpa-psk` is required, or nmcli refuses the profile.
3. **`unset PSK`** clears the password from the shell.

### Already saved VENUE without a password?

Don't run `con add` again, or you'll end up with two VENUE profiles. Add the password to the profile you have:

```bash
read -rsp "Venue Wi-Fi password: " PSK; echo

sudo nmcli con modify VENUE \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "$PSK"

unset PSK
```

`con modify` updates the existing profile and keeps the same UUID.

## 5. Connect and check

```bash
sudo nmcli con up VENUE
nmcli dev status | grep wlan0          # connected  VENUE
sudo travel-vpn status
sudo travel-vpn check
```

You want the tunnel **UP**, the kill switch **ON**, and a public IP that belongs to your VPN. If the venue has a sign-in page, the tunnel can't connect until you finish step 6.

## 6. Get through a sign-in page

The kill switch blocks the sign-in page, so open it for a moment:

```bash
sudo travel-vpn off
```

1. On your phone or laptop (on the private Wi-Fi), open `http://neverssl.com`. The venue's sign-in page appears.
2. Enter your room number, last name, or accept the terms.
3. Turn protection back on:

```bash
sudo travel-vpn on
sudo travel-vpn status
```

> ⚠️ While it's off, devices are **not protected**. Keep it short. A reboot always turns the kill switch back on.

In Brave, you may need to turn off Shields and Secure DNS for the sign-in page, then turn them back on.

## Where the profile and its UUID are saved

When the profile is created, NetworkManager generates a random UUID for it and writes everything to one file:

```
/etc/NetworkManager/system-connections/VENUE.nmconnection
```

It looks roughly like this:

```ini
[connection]
id=VENUE
uuid=<random-uuid>
type=wifi
interface-name=wlan0

[wifi]
ssid=<Your_Venue_SSID>

[ipv4]
method=auto
```

- **The UUID belongs to the profile, not the network.** Run `con add` twice and you get two VENUE profiles with two different UUIDs that join the same network.
- **The file is readable only by root**, because it can hold the Wi-Fi password.

See it yourself:

```bash
nmcli -f NAME,UUID,TYPE,DEVICE con show                            # every profile and its UUID
nmcli -g connection.uuid con show VENUE                             # just VENUE's UUID
sudo ls -l /etc/NetworkManager/system-connections/                  # the profile files
sudo grep -v psk= /etc/NetworkManager/system-connections/VENUE.nmconnection   # settings, password hidden
```

Done with the venue? Delete the profile so the Pi doesn't keep it. Fewer saved networks means fewer wrong ones for the Pi to join on its own:

```bash
sudo nmcli con delete VENUE
```

## Troubleshooting

| What you see | Fix |
|---|---|
| `sudo: dev: command not found` | You left out `nmcli`. Use `sudo nmcli dev ...` |
| `command not found: nmcli` | You're on the Mac, not the Pi. SSH into the Pi first |
| `not authorized` | Add `sudo` to the rescan |
| `Scanning not allowed immediately following previous scan` | Wait 30 to 60 seconds, then rescan. `nmcli dev wifi list` still shows the last results |
| `Scanning not allowed while unavailable or activating` | `wlan0` is still connecting. Wait until `nmcli dev status` shows it connected |
| `unknown connection` | You used the Wi-Fi name. Use the profile name (`con-name`) |
| `802-11-wireless-security.key-mgmt: property is missing` | Add `wifi-sec.key-mgmt wpa-psk`, as in 4b |
| "There are N other connections with the name ..." | Earlier attempts left copies. `nmcli con show` lists them; delete each with `sudo nmcli con delete uuid <UUID>`, then add one fresh profile |
| Connected, but nothing loads | The venue has a sign-in page. Do step 6 |
| Nothing loads, and `iw dev wlan0 link` shows your own private Wi-Fi name | `wlan0` joined your own hotspot, not the venue. See [The router connected to itself](../router-connected-to-itself/README.md) |
| Tunnel won't come back after signing in | `sudo systemctl restart wg-quick@wg0`, wait 15 seconds, then `sudo travel-vpn status` |
