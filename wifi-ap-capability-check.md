# TravelPi Router: Wi-Fi Access Point Capability Check

## 1. Purpose

This procedure checks whether the Wi-Fi adapter that will host your private network advertises support for **Wi-Fi Access Point (AP) mode**.

For the TravelPi Router project, this is an important prerequisite because the Raspberry Pi 5 is intended to:

- Connect to an existing home router over Wi-Fi for upstream internet access.
- Broadcast a separate private Wi-Fi network for client devices.
- Run Pi-hole for DNS filtering.
- Route traffic between the private network and the upstream connection.

**Operating system:** Raspberry Pi OS Trixie  
**Hardware:** Raspberry Pi 5  
**Wireless interfaces:**

| Interface | Role |
|---|---|
| `wlan0` | Upstream: the Pi's built-in Wi-Fi, connected to the home router |
| `wlan1` | Access point: the private network, run by hostapd |

> **Safety note:** These commands are diagnostic only. They do not change network interfaces, routing, firewall rules, or the existing home network.

---

## 2. Prerequisites

Open a terminal on the Raspberry Pi.

Verify that both wireless interfaces exist:

```bash
ip -br link
```

You should see both `wlan0` and `wlan1` in the list. If `wlan1` is missing, check that the second Wi-Fi adapter is plugged in and recognized:

```bash
lsusb
```

Check that the `iw` utility is installed:

```bash
iw --version
```

If `iw` is missing, install it:

```bash
sudo apt update
sudo apt install iw
```

---

## 3. Run the Check

Run the following commands to check whether `wlan1`'s wireless radio advertises AP mode support.

```bash
p=$(cat /sys/class/net/wlan1/phy80211/name)
iw phy "$p" info | grep -q '\* AP$' && echo "wlan1 ($p): AP supported" || echo "wlan1 ($p): no AP"
```

To check another interface, replace both `wlan1`s with its name.

### Expected output

Example when AP mode is advertised:

```text
wlan1 (phy1): AP supported
```

Example when the check does not find AP mode:

```text
wlan1 (phy1): no AP
```

The output depends on the wireless hardware, driver, and system configuration.

---

## 4. Line-by-Line Explanation

### Line 1: Identify the physical wireless radio

```bash
p=$(cat /sys/class/net/wlan1/phy80211/name)
```

- `/sys/class/net/wlan1/phy80211/name` is a small file the kernel creates for every Wi-Fi interface. It holds the name of the radio behind it.
- `cat` reads that file.
- `$(...)` runs a command and substitutes its output.
- `p=$(...)` stores the result in the variable `p`.

Example:

```text
p=phy1
```

The PHY represents the underlying wireless radio. Multiple wireless interfaces can sometimes share the same PHY.

### Line 2: Inspect supported modes and display the result

```bash
iw phy "$p" info | grep -q '\* AP$' && echo "wlan1 ($p): AP supported" || echo "wlan1 ($p): no AP"
```

**The search:**

- `iw phy "$p" info` displays information about the wireless PHY. The quotes around `$p` are a good habit: they keep the value in one piece.
- `|` passes the output to the next command.
- `grep -q` searches quietly and returns a status code.
- `\*` matches a literal asterisk.
- `AP` identifies Access Point mode.
- `$` anchors the match to the end of a line, so `* AP/VLAN` doesn't count.

The check looks for a line ending in:

```text
* AP
```

If the pattern is found, `grep` returns success. Otherwise, it returns failure.

**The result:**

- `&&` runs the first `echo` if `grep` succeeded.
- `||` runs the second `echo` if `grep` failed.
- `echo` prints the result.

---

## 5. Bash Operator Reference

| Syntax | Meaning |
|---|---|
| `$p` | Expands the value of variable `p` |
| `"$p"` | Same, kept as one piece even if it contains spaces |
| `$(command)` | Executes a command and captures its output |
| `\|` | Pipes output into another command |
| `&&` | Executes the next command when the previous command succeeds |
| `\|\|` | Executes the next command when the previous command fails |
| `grep -q` | Searches without printing matching lines |

---

## 6. Alternative Diagnostic Command

A shorter way to see the supported modes for `wlan1`'s radio:

```bash
iw phy "$(cat /sys/class/net/wlan1/phy80211/name)" info | grep -A 10 "Supported interface modes"
```

Look for an entry similar to:

```text
Supported interface modes:
         * IBSS
         * managed
         * AP
         * monitor
```

The presence of `* AP` means the wireless PHY advertises Access Point mode.

To see everything for every radio at once, run `iw list` and scroll to each `Supported interface modes` section.

---

## 7. Important Limitation: AP Mode Is Not the Whole Router

A successful AP capability check does **not** guarantee that the complete TravelPi Router configuration will work.

The project requires two wireless roles:

1. **Upstream client mode** on `wlan0`: connect to the existing home router.
2. **Access Point mode** on `wlan1`: broadcast a private Wi-Fi network for client devices.

Because each role has its own radio, they don't compete:

- The access point can use any channel, independent of the home router's channel.
- You don't need the radio to support client and AP at the same time.

> **Single-radio setups:** if you ever run both roles on one adapter (for example, a virtual AP on the built-in Wi-Fi), the radio must support both at once (`valid interface combinations` in `iw list`), and the access point is locked to the **same channel** as the upstream network. That's the most common surprise with one-radio travel routers.

Additional checks for `wlan1`:

- Whether the adapter's driver is included in Raspberry Pi OS or needs to be installed.
- Whether hostapd starts cleanly on it (see Troubleshooting).

Do not change the existing Wi-Fi connection on `wlan0` until these capabilities have been verified.

---

## 8. TravelPi Router Verification Checklist

Use this checklist before proceeding with access point configuration.

- [ ] Confirm `wlan0` and `wlan1` both exist.
- [ ] Confirm the `iw` utility is installed.
- [ ] Identify the wireless PHY associated with `wlan1`.
- [ ] Confirm AP mode is advertised on `wlan1`.
- [ ] Record the existing upstream connection on `wlan0` and the default route (`ip route`).
- [ ] Plan firewall and routing changes before applying them.
- [ ] Preserve the existing home network configuration.

---

## 9. Troubleshooting

### Error: `No such file or directory`

Check whether the interface has an associated PHY:

```bash
ls -l /sys/class/net/wlan1/phy80211/
```

If the directory is missing, verify that `wlan1` is a wireless interface and that the adapter's driver has loaded (`lsusb`, then `dmesg | grep -i wlan1`).

### Result: `no AP`

Inspect the complete capability list:

```bash
iw list
```

If AP mode is absent, do not assume that the adapter can host the private Wi-Fi network. Investigate the hardware and driver before proceeding, or choose an adapter known to support AP mode on Linux.

### Result: `AP supported`, but the access point does not start

Check the wireless service and system logs:

```bash
rfkill list
```

```bash
iw dev
```

```bash
journalctl -b | grep -Ei 'wlan1|hostapd|wifi|firmware'
```

These commands help investigate radio blocking, existing wireless interfaces, service errors, and driver or firmware messages.

---

## 10. Project Status

Record the test results here.

| Item | Result |
|---|---|
| Raspberry Pi model | Raspberry Pi 5 |
| Operating system | Raspberry Pi OS Trixie |
| Upstream interface | `wlan0` (built-in Wi-Fi) |
| Access point interface | `wlan1` |
| Associated PHY for `wlan1` | To be recorded |
| AP mode advertised on `wlan1` | To be recorded |
| Pi-hole | Working |
| Firewall and routing | Verify before deployment |

---

## 11. Next Step

Once the wireless capabilities have been verified, set up the access point with the **[private Wi-Fi guide](private-wifi-setup.md)**, then follow the TravelPi Router configuration plan:

1. Confirm the upstream Wi-Fi connection on `wlan0`.
2. Configure the private access point on `wlan1`.
3. Configure DHCP and DNS for the private network.
4. Verify Pi-hole integration.
5. Configure forwarding and firewall rules.
6. Test private-network isolation and internet connectivity.
7. Confirm the existing home network remains unaffected.
