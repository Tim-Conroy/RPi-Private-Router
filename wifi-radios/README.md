# wifi-radios.sh: tell your Wi-Fi radios apart at a glance

A small script that prints one line per Wi-Fi radio: its interface name, MAC address, driver, phy, mode, whether it's built in or a USB adapter, and what NetworkManager is doing with it.

> Part of the [RPi Private Router](../README.md) project. Featured in the video **How Linux Finds, Names, and Manages Your Wi-Fi Radios (Raspberry Pi 5)**.

## Why

With two radios, the names `wlan0` and `wlan1` can swap after a reboot, depending on which radio the kernel finds first. The **MAC address** and the **driver** don't change, so they're the reliable way to tell which radio is which. This script shows all of it at once.

## Example output

```
$ wifi-radios.sh
IFACE    MAC                 DRIVER           PHY    MODE      RADIO        NM-STATE
-----    ---                 ------           ---    ----      -----        --------
wlan0    2c:cf:67:xx:xx:xx   brcmfmac         phy0   managed   built-in     connected
wlan1    00:c0:ca:xx:xx:xx   rtw88_8821au     phy1   AP        USB adapter  unmanaged
```

(MAC addresses partly hidden.)

| Column | Meaning |
|---|---|
| IFACE | The interface name (`wlan0`, `wlan1`) |
| MAC | The MAC address in use right now. `2c:cf:67` = Raspberry Pi, `00:c0:ca` = ALFA |
| DRIVER | The kernel driver. `brcmfmac` = Pi's built-in radio, `rtw88_…` = ALFA |
| PHY | The radio's phy name in cfg80211 (`phy0`, `phy1`, …) |
| MODE | `managed` = client, `AP` = access point, `monitor`, … |
| RADIO | Built in, or a USB adapter |
| NM-STATE | NetworkManager's view: `connected`, `disconnected`, `unmanaged`, … |

## Install it so you can run it from anywhere

Run these on the Pi.

**1. Make a folder for your own commands:**

```bash
mkdir -p ~/.local/bin
```

**2. Put the script in it.** Either download it straight from GitHub:

```bash
wget -O ~/.local/bin/wifi-radios.sh https://raw.githubusercontent.com/Tim-Conroy/RPi-Private-Router/master/wifi-radios/wifi-radios.sh
```

or create the file and paste the script in:

```bash
nano ~/.local/bin/wifi-radios.sh
```

Paste the contents of [wifi-radios.sh](wifi-radios.sh), save with **Ctrl+O**, press **Enter**, then exit with **Ctrl+X**.

**3. Make it runnable:**

```bash
chmod +x ~/.local/bin/wifi-radios.sh
```

**4. Log out and back in (or reboot).** On Raspberry Pi OS and other Debian-based systems, `~/.local/bin` is added to your command path at login once the folder exists. After that, run it from any directory:

```bash
wifi-radios.sh
```

### If you get "command not found"

Check whether `~/.local/bin` is on your path:

```bash
echo "$PATH" | tr ':' '\n' | grep local/bin
```

If nothing prints, add it and reload your profile:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
source ~/.profile
```

Until then, you can always run it with the full path: `~/.local/bin/wifi-radios.sh`

## Requirements

- Linux with Wi-Fi radios (any distro: it reads `/sys/class/net`)
- Optional: `iw` for the MODE column and `nmcli` for the NM-STATE column. Both come with Raspberry Pi OS. Without them, those columns show `-`.
- No `sudo` needed.
