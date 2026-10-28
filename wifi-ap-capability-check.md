# TravelPi Router: Wi-Fi Access Point Capability Check

## 1. Purpose

This procedure checks whether the Raspberry Pi's wireless hardware and driver advertise support for **Wi-Fi Access Point (AP) mode**.

For the TravelPi Router project, this is an important prerequisite because the Raspberry Pi 5 is intended to:

- Connect to an existing home router over Wi-Fi for upstream internet access.
- Broadcast a separate private Wi-Fi network for client devices.
- Run Pi-hole for DNS filtering.
- Route traffic between the private network and the upstream connection.

**Operating system:** Raspberry Pi OS  
**Hardware:** Raspberry Pi 5  
**Wireless interface:** `wlan0`

> **Safety note:** These commands are diagnostic only. They do not change network interfaces, routing, firewall rules, or the existing home network.

---

## 2. Prerequisites

Open a terminal on the Raspberry Pi.

Verify that the wireless interface exists:

```bash
ip link show wlan0
```

List available network interfaces:

```bash
ls /sys/class/net
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

## 3. The Original Bash For Loop

Run the following script to check whether `wlan0`'s associated wireless PHY advertises AP mode support.

```bash
for i in $(ls /sys/class/net | grep wlan0); do
    p=$(cat /sys/class/net/$i/phy80211/name)

    iw phy $p info | grep -q '\* AP$' \
    && echo "$i ($p): AP supported" \
    || echo "$i ($p): no AP"
done
```

### Expected output

Example when AP mode is advertised:

```text
wlan0 (phy0): AP supported
```

Example when the check does not find AP mode:

```text
wlan0 (phy0): no AP
```

The output depends on the wireless hardware, driver, and system configuration.

---

## 4. Line-by-Line Explanation

### Step 1: Find the wireless interface

```bash
for i in $(ls /sys/class/net | grep wlan0); do
```

- `ls /sys/class/net` lists the network interfaces.
- `grep wlan0` filters the list for names containing `wlan0`.
- `$(...)` executes a command and substitutes its output.
- `for i in ...; do` assigns each matching name to the variable `i`.

For this project, the expected value is:

```text
i=wlan0
```

### Step 2: Identify the physical wireless radio

```bash
p=$(cat /sys/class/net/$i/phy80211/name)
```

- `$i` expands to the interface name.
- `cat` reads the wireless PHY name associated with that interface.
- `p=$(...)` stores the result in the variable `p`.

Example:

```text
p=phy0
```

The PHY represents the underlying wireless radio. Multiple wireless interfaces can sometimes share the same PHY.

### Step 3: Inspect supported wireless modes

```bash
iw phy $p info | grep -q '\* AP$'
```

- `iw phy $p info` displays information about the wireless PHY.
- `|` passes the output to the next command.
- `grep -q` searches quietly and returns a status code.
- `\*` matches a literal asterisk.
- `AP` identifies Access Point mode.
- `$` anchors the match to the end of a line.

The script checks for a line ending in:

```text
* AP
```

If the pattern is found, `grep` returns success. Otherwise, it returns failure.

### Step 4: Display the result

```bash
&& echo "$i ($p): AP supported" \
|| echo "$i ($p): no AP"
```

- `&&` executes the first `echo` if the preceding command succeeds.
- `||` executes the second `echo` if the preceding command fails.
- `echo` prints the result.
- `\` continues a command onto the next line.

The result indicates whether the script found the AP mode entry.

### Step 5: Finish the loop

```bash
done
```

The `done` keyword marks the end of the loop.

Bash repeats the loop body for each matching interface name.

---

## 5. Bash Operator Reference

| Syntax | Meaning |
|---|---|
| `$i` | Expands the value of variable `i` |
| `$(command)` | Executes a command and captures its output |
| `\|` | Pipes output into another command |
| `&&` | Executes the next command when the previous command succeeds |
| `\|\|` | Executes the next command when the previous command fails |
| `\` | Continues a command onto the next line |
| `grep -q` | Searches without printing matching lines |
| `done` | Ends a loop |

---

## 6. Alternative Diagnostic Command

A simpler way to inspect supported wireless interface modes is:

```bash
iw list | grep -A 15 "Supported interface modes"
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

For a more focused view of the supported modes, use:

```bash
iw list
```

Then locate the `Supported interface modes` section.

---

## 7. Important Limitation: AP Mode Is Not the Whole Router

A successful AP capability check does **not** guarantee that the complete TravelPi Router configuration will work.

The project requires two wireless roles:

1. **Upstream client mode:** Connect to the existing home router.
2. **Access Point mode:** Broadcast a private Wi-Fi network for client devices.

The ability to perform both roles simultaneously depends on the adapter, driver, and supported wireless interface combinations.

Inspect the relevant capabilities with:

```bash
iw list
```

Look for the `valid interface combinations` section, if present.

Additional checks may be necessary to confirm:

- Whether the radio supports concurrent client and AP operation.
- Whether the driver permits the required combination.
- Whether the wireless channels must match.
- Whether the access point can be configured without disrupting the upstream connection.

Do not change the existing Wi-Fi connection until these capabilities have been verified.

---

## 8. TravelPi Router Verification Checklist

Use this checklist before proceeding with access point configuration.

- [ ] Confirm `wlan0` exists.
- [ ] Confirm the `iw` utility is installed.
- [ ] Identify the wireless PHY associated with `wlan0`.
- [ ] Confirm whether AP mode is advertised.
- [ ] Inspect `valid interface combinations`, if available.
- [ ] Verify whether simultaneous client and AP operation is supported.
- [ ] Record the existing upstream connection and default route.
- [ ] Plan firewall and routing changes before applying them.
- [ ] Preserve the existing home network configuration.

---

## 9. Troubleshooting

### Error: `No such file or directory`

Check whether the interface has an associated PHY:

```bash
ls -l /sys/class/net/wlan0/phy80211/
```

If the directory is missing, verify that `wlan0` is a wireless interface and that the wireless driver has loaded.

### Result: `no AP`

Inspect the complete capability list:

```bash
iw list
```

If AP mode is absent, do not assume that the adapter can host the private Wi-Fi network. Investigate the hardware and driver before proceeding.

### Result: `AP supported`, but the access point does not start

Check the wireless service and system logs:

```bash
rfkill list
```

```bash
iw dev
```

```bash
journalctl -b | grep -Ei 'wlan0|hostapd|wifi|firmware'
```

These commands help investigate radio blocking, existing wireless interfaces, service errors, and driver or firmware messages.

---

## 10. Project Status

Record the test results here.

| Item | Result |
|---|---|
| Raspberry Pi model | Raspberry Pi 5 |
| Operating system | Raspberry Pi OS |
| Wireless interface | `wlan0` |
| Associated PHY | To be verified |
| AP mode advertised | To be verified |
| Concurrent client + AP support | To be verified |
| Pi-hole | Working |
| Firewall and routing | Verify before deployment |

---

## 11. Next Step

Once the wireless capabilities have been verified, proceed with the TravelPi Router configuration plan:

1. Confirm the upstream Wi-Fi connection.
2. Determine whether the existing wireless adapter can handle both roles.
3. Configure the private access point.
4. Configure DHCP and DNS for the private network.
5. Verify Pi-hole integration.
6. Configure forwarding and firewall rules.
7. Test private-network isolation and internet connectivity.
8. Confirm the existing home network remains unaffected.
