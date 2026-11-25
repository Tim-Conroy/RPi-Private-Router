#!/bin/bash
# wifi-radios.sh
# Show every Wi-Fi interface with its MAC address, driver, phy,
# mode, where the radio is attached, and NetworkManager's state.
#
# Use it to tell your radios apart by MAC address and driver,
# even if the wlan0 / wlan1 names swap after a reboot.
#
# Usage:  wifi-radios.sh

shopt -s nullglob

FORMAT="%-8s %-19s %-16s %-6s %-9s %-12s %s\n"

found=0
printf "$FORMAT" "IFACE" "MAC" "DRIVER" "PHY" "MODE" "RADIO" "NM-STATE"
printf "$FORMAT" "-----" "---" "------" "---" "----" "-----" "--------"

# Every Wi-Fi interface has a "phy80211" link pointing to its radio (phy)
for p in /sys/class/net/*/phy80211; do
    found=1
    dev=$(dirname "$p")
    name=$(basename "$dev")

    # MAC address currently in use
    mac=$(cat "$dev/address" 2>/dev/null)

    # Driver attached to the radio
    driver="-"
    if [ -e "$dev/device/driver" ]; then
        driver=$(basename "$(readlink -f "$dev/device/driver")")
    fi

    # phy name (phy0, phy1, ...)
    phy=$(cat "$p/name" 2>/dev/null)

    # Interface mode: managed (client), AP, monitor ...
    mode=""
    if command -v iw >/dev/null 2>&1; then
        mode=$(iw dev "$name" info 2>/dev/null | awk '/type/ {print $2; exit}')
    fi

    # Built-in radio or USB adapter?
    if readlink -f "$dev/device" | grep -q "/usb"; then
        radio="USB adapter"
    else
        radio="built-in"
    fi

    # NetworkManager state: connected, disconnected, unmanaged ...
    state=""
    if command -v nmcli >/dev/null 2>&1; then
        state=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null \
                | awk -F: -v d="$name" '$1 == d {print $2; exit}')
    fi

    printf "$FORMAT" "$name" "${mac:--}" "$driver" "${phy:--}" \
           "${mode:--}" "$radio" "${state:--}"
done

if [ "$found" -eq 0 ]; then
    echo "No Wi-Fi interfaces found."
    echo "Check: lsusb, rfkill list, and sudo dmesg | grep -i firmware"
    exit 1
fi
