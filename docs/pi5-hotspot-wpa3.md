# Upgrading a Raspberry Pi 5 Hotspot from WPA2 to WPA3

A step-by-step record of moving a Raspberry Pi 5 Wi-Fi access point (hostapd on Debian Trixie) from **WPA2-only** to **WPA2/WPA3 transition mode**, including what was discovered along the way and the corrections made after review.

> **Security note:** Every network name, address, username and password in this document is a placeholder. Never commit your real `hostapd.conf`; it contains your Wi-Fi passphrase. See [Keeping secrets out of this repo](#9-keeping-secrets-out-of-this-repo).

---

## Contents

1. [Result](#1-result)
2. [Environment](#2-environment)
3. [Placeholders used](#3-placeholders-used)
4. [Why WPA3, and why transition mode](#4-why-wpa3-and-why-transition-mode)
5. [Procedure](#5-procedure)
6. [Optional extras](#6-optional-extras)
7. [Discovery log](#7-discovery-log)
8. [Review: errors and corrections](#8-review-errors-and-corrections)
9. [Keeping secrets out of this repo](#9-keeping-secrets-out-of-this-repo)
10. [Teaching materials built from this work](#10-teaching-materials-built-from-this-work)
11. [Appendix: grep cheat sheet](#appendix-grep-cheat-sheet)

---

## 1. Result

- The Pi's private hotspot now advertises **WPA2/WPA3 Personal**.
- WPA3-capable devices connect with SAE. Older WPA2 devices still connect.
- The Wi-Fi password did not change.
- A security audit that had warned *"Wi-Fi uses WPA2 only; WPA3 (SAE) is stronger"* no longer applies.

## 2. Environment

| Item | Value |
|---|---|
| Hardware | Raspberry Pi 5 |
| OS | Debian 13 "Trixie" |
| Hotspot interface | USB Wi-Fi adapter (`wlan1`, type AP) |
| Upstream connection | Built-in Wi-Fi (`wlan0`, type managed) to the home router; **not changed** |
| Access point software | `hostapd`, config at `/etc/hostapd/hostapd.conf` |
| How hostapd starts | Not the standard `hostapd` systemd service (see [Discovery log](#7-discovery-log)) |
| Client used to verify | MacBook (macOS) |

## 3. Placeholders used

| Placeholder | Meaning | Example |
|---|---|---|
| `<ap-iface>` | Interface running the hotspot | `wlan1` |
| `<phyN>` | Radio behind that interface | `phy1` |
| `<pi-user>` | Your login name on the Pi | n/a |
| `<pi-ip>` | The Pi's address on your home network | n/a |

## 4. Why WPA3, and why transition mode

| Feature | What it does |
|---|---|
| **SAE handshake** | Replaces the WPA2 four-way handshake with one that can't be captured and brute-forced offline, so your password can't be guessed offline. |
| **Protected Management Frames (PMF)** | Stops forged "disconnect" frames that kick devices off the network. Required by WPA3. |
| **Transition mode** | Runs WPA2 and WPA3 side by side, so older devices (smart plugs, cameras, printers, pre-2019 phones and laptops) keep working. |

---

## 5. Procedure

Each step notes **where** to run it:

- 🟢 **Pi terminal:** on the Pi's own keyboard, or in an SSH session to the Pi.
- 🔵 **Laptop:** in the Terminal app, or the menu bar, on your laptop.

### Step 1: Get safe access to the Pi

**Never edit Wi-Fi settings over the Wi-Fi you are changing.** If the hotspot fails to come back, you lose your connection. In order of safety:

1. **Keyboard and monitor** plugged straight into the Pi (used for this build).
2. **Ethernet cable**, if the Pi's firewall allows it.
3. **SSH over the home network**, if the Pi's firewall allows SSH on that interface.

🔵 To find the Pi on the home network from a laptop:

```bash
arp -a
```

Raspberry Pi 5 network interfaces often have MAC addresses starting with `2c:cf:67` or `d8:3a:dd` (Raspberry Pi vendor prefixes). The `.1` address on most home networks is the **router**, not the Pi.

🔵 Then connect (no `sudo`):

```bash
ssh <pi-user>@<pi-ip>
```

> In this build, SSH from the home network was blocked by the Pi's firewall, which is a good security posture, so a keyboard and monitor were used.

### Step 2: Check the adapter supports WPA3

WPA3 support depends on the **Wi-Fi adapter's driver**, not on the Pi or the OS. Debian Trixie's `hostapd` already supports SAE.

🟢 Find which radio sits behind the hotspot interface (`wiphy 1` means `phy1`):

```bash
iw dev <ap-iface> info | grep wiphy
```

🟢 Check for **SAE**, the WPA3 handshake:

```bash
iw phy <phyN> info | grep -i "sae"
```

Good result: `SAE_OFFLOAD_AP`, `Device supports SAE with AUTHENTICATE command`, or `00-0f-ac:8`.

🟢 Check for **CMAC**, needed for PMF:

```bash
iw phy <phyN> info | grep -i "cmac"
```

Good result: `CMAC-128 (00-0f-ac:6)`.

**Both checks must return results.** If either is empty, the adapter can't run a WPA3 access point. Both were positive in this build.

### Step 3: Find what runs the access point

These commands only read information.

🟢 Which interface is the hotspot? Look for `type AP`. The home connection shows `type managed`.

```bash
iw dev
```

🟢 Which program runs it, and with which config file?

```bash
ps aux | grep -E "hostapd|wpa_supplicant" | grep -v grep
```

The hostapd line ends with the config path, here `/etc/hostapd/hostapd.conf`.

🟢 Optional: which systemd unit (if any) launched it:

```bash
systemctl status $(pgrep -o hostapd)
```

> `systemctl is-active hostapd` reported **inactive** even though hostapd was running, because it wasn't started by the standard `hostapd` service. Trust `iw dev` and `ps` instead.

### Step 4: Back up and edit `hostapd.conf`

🟢 Back up:

```bash
sudo cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak
```

🟢 Optional, for screen recording: view the file with password lines hidden:

```bash
sudo grep -vE "passphrase|password" /etc/hostapd/hostapd.conf
```

🟢 Open it:

```bash
sudo nano /etc/hostapd/hostapd.conf
```

**Change one line and add two** so the block reads:

```ini
wpa=2
wpa_key_mgmt=WPA-PSK SAE
rsn_pairwise=CCMP
ieee80211w=1
sae_pwe=2
```

| Setting | Before | After | Why |
|---|---|---|---|
| `wpa_key_mgmt` | `WPA-PSK` | `WPA-PSK SAE` | WPA3 and WPA2 side by side (transition mode) |
| `ieee80211w` | *(absent)* | `1` | PMF enabled, optional for WPA2 clients |
| `sae_pwe` | *(absent)* | `2` | WPA3 handshake compatible with old and new clients |

- The existing `wpa_passphrase` is reused for WPA3. No new password is needed.
- Make sure there is **only one** `ieee80211w` line in the file.

**Save and exit nano:**

| Keys | Action |
|---|---|
| `Ctrl` + `O` | Save ("write out"). That's the **letter O**, not zero. |
| `Enter` | Confirm the file name |
| `Ctrl` + `X` | Exit nano |

### Step 5: Reboot and verify

Because hostapd isn't started by the standard service, a reboot is the simplest reliable way to apply the change.

🟢

```bash
sudo reboot
```

🟢 The hotspot is back: `<ap-iface>` shows `type AP`:

```bash
iw dev
```

🟢 The settings are saved:

```bash
sudo grep -E "wpa_key_mgmt|ieee80211w|sae_pwe" /etc/hostapd/hostapd.conf
```

🔵 **The best proof (macOS):** connect to the hotspot, hold **Option**, click the Wi-Fi icon in the menu bar. **Security** should read **WPA2/WPA3 Personal**.

If the hotspot doesn't come back:

```bash
sudo journalctl -b | grep -i hostapd
```

### Rollback

🟢

```bash
cd /etc/hostapd
sudo cp hostapd.conf.bak hostapd.conf
sudo reboot
```

---

## 6. Optional extras

### Live check: which clients are on WPA3

`hostapd_cli` returned `No such file or directory` because the config had no control interface.

🟢 Make a second backup, so the first one stays untouched:

```bash
sudo cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak2
```

🟢 Open the config and add these lines at the end of the file:

```ini
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
```

`ctrl_interface_group=0` limits access to root, which is why the commands below use `sudo`. Save, then `sudo reboot`.

🟢 Check the live config:

```bash
sudo hostapd_cli -i <ap-iface> get_config
```

Look for `key_mgmt=WPA-PSK SAE`.

🟢 List connected clients and their security type:

```bash
sudo hostapd_cli -i <ap-iface> all_sta | grep -E "^[0-9a-f]{2}:|AKMSuiteSelector"
```

| AKM value | Meaning |
|---|---|
| `00-0f-ac-8` | Client connected with **WPA3 (SAE)** |
| `00-0f-ac-2` | Client connected with **WPA2 (PSK)** |

### WPA3 only, later

Once every device connects fine, change these two lines in `/etc/hostapd/hostapd.conf`:

```ini
wpa_key_mgmt=SAE
ieee80211w=2
```

Then save (`Ctrl`+`O`, `Enter`, `Ctrl`+`X`) and run `sudo reboot`.

> ⚠️ WPA2-only devices will stop connecting.

---

## 7. Discovery log

What was found, in order, and what it changed.

| # | Finding | How it was found | What it meant |
|---|---|---|---|
| 1 | A security audit flagged the hotspot as "WPA2 only" | Audit script output | Goal: enable WPA3 |
| 2 | The hotspot is on `wlan1`, likely a USB adapter | Interface name; Pi 5 built-in Wi-Fi is usually `wlan0` | Good news: the Pi's built-in radio is unreliable for WPA3 in AP mode, while many USB adapters handle it well |
| 3 | The adapter supports SAE and CMAC | `iw phy ... info \| grep -i` | WPA3 is possible |
| 4 | SSH to the Pi over the home network was refused | SSH attempt | The Pi's firewall only allows SSH from the private side, so a keyboard and monitor were used |
| 5 | An early SSH attempt hung | Targeted the `.1` address | That address was the home router, not the Pi; the Pi's real address was found with `arp -a` |
| 6 | `systemctl is-active hostapd` → `inactive` | systemctl | hostapd isn't started by the standard unit, so don't trust this check |
| 7 | NetworkManager lists only the home connection | `nmcli con show --active` | The hotspot isn't managed by NetworkManager |
| 8 | `wlan1` is `type AP`, `wlan0` is `type managed` | `iw dev` | Confirmed which interface to change and which to leave alone |
| 9 | hostapd runs with `/etc/hostapd/hostapd.conf` | `ps aux` | Found the file to edit |
| 10 | The config had `wpa=2`, `wpa_key_mgmt=WPA-PSK`, `rsn_pairwise=CCMP` | `grep -vE "passphrase\|password"` | Exactly one line to change, two to add |
| 11 | After the reboot, the Mac showed WPA2/WPA3 Personal | macOS Option-click | ✅ Upgrade worked |
| 12 | `hostapd_cli` → "No such file or directory" | hostapd_cli | No `ctrl_interface`; fixed via the optional extra |

## 8. Review: errors and corrections

Issues found when reviewing the original working session, and how this document handles them.

| Issue | Correction |
|---|---|
| The adapter check was done **before** getting safe access to the Pi | Reordered: [Step 1](#step-1-get-safe-access-to-the-pi) is now safe access. The checks only read information, but you need to be on the Pi to run them. |
| `ssh` was run with `sudo` | Don't. `sudo ssh` uses root's keys and `known_hosts`, not yours. |
| A search for the SSID in `/etc` used case-sensitive `grep -rl` and found nothing | Use `grep -ril` so capitalization differences don't hide a match. |
| `grep` on `hostapd.conf` without `sudo` | The file can be root-only because it contains the passphrase. Use `sudo grep`. |
| Relying on `systemctl is-active hostapd` | Misleading for non-standard launches. Use `iw dev`, `ps`, or `systemctl status $(pgrep -o hostapd)`. |
| "WPA3 only" instructions didn't say to apply the change | Added: save, then `sudo reboot`. |
| Restarting hostapd | A plain `systemctl restart hostapd` won't work if hostapd is started elsewhere. Reboot, or find the owning unit first. |

## 9. Keeping secrets out of this repo

- **Never commit** `hostapd.conf`, its `.bak` copies, or anything containing `wpa_passphrase` or `sae_password`.
- Use placeholders (`<ap-iface>`, `<pi-ip>`, ...) in docs and screenshots.
- Before screen recording, view configs with `sudo grep -vE "passphrase|password"`.
- Suggested `.gitignore`:

```gitignore
# Wi-Fi configs contain passphrases
hostapd.conf
hostapd.conf.*
*.bak
*.bak2
wpa_supplicant*.conf
```

- Optional check before every commit:

```bash
git diff --cached | grep -iE "passphrase|sae_password|psk="
```

No output means nothing sensitive is staged.

## 10. Teaching materials built from this work

| Item | Format | Notes |
|---|---|---|
| Step-by-step guide | Word (.docx) | Same procedure, placeholders only |
| Video slide deck | 20 slides, 16:9 | Speaker-note narration on every slide |
| YouTube thumbnail | 1280×720 PNG | Based on the deck's cover design |

Design decisions for the deck:

- **Accessibility:** headings 80 px; body 34–40 px; commands 30–44 px bold. High-contrast white or mint text on navy, near-black text on cream.
- **Terminal badges:** each command slide shows 🟢 *Raspberry Pi terminal* or 🔵 *Laptop terminal* in the corner. The badges use words as well as color.
- **Placeholder keys:** any slide that uses `<ap-iface>`, `<phyN>`, `<pi-user>` or `<pi-ip>` explains it on that slide.
- **No secrets on screen:** placeholders only, no real names, addresses or passwords.
- **Trademarks avoided:** a generic circuit board instead of the Raspberry Pi logo, a generic wireless icon instead of the Bluetooth logo, and an orange play box instead of the YouTube logo.

---

## Appendix: grep cheat sheet

| Option | What it does |
|---|---|
| `a \| b` | Send command a's output into command b |
| `-i` | Ignore upper and lower case |
| `-E "x\|y"` | Match x **or** y |
| `-v` | Show every line **except** matches |
| `-A 12` | Show 12 lines **after** each match |
| `-c` | Count matching lines (0 = not found) |
| `-r` / `-l` | Search folders recursively / list matching files only |
