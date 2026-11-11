# RPi Private Router: A Secure, Ad-Free Raspberry Pi 5 Wi-Fi Hotspot for Home and Travel

A Raspberry Pi 5 that joins an upstream Wi-Fi on `wlan0` (home, Starlink or a campground) and broadcasts its own private, ad-free network on `wlan1`. It's protected with WPA3, filtered by [Pi-hole](https://pi-hole.net/), and can send all traffic through a WireGuard VPN.

> 📺 **New here?** Watch **Part 1 of 2** on my YouTube channel for the full setup: https://youtu.be/I8HdF6vV1IE

## Project guides

| Step | Guide |
|---|---|
| 1 | [Wi-Fi access point capability check](wifi-ap-capability-check.md) |
| 2 | [Install Pi-hole, step by step](Pi-hole-Installation-Guide.md) |
| 3 | [Private Wi-Fi: hostapd access point on `wlan1`, with Pi-hole handing out addresses](private-wifi-setup.md) |
| 4 | [Upgrade the private Wi-Fi from WPA2 to WPA3 (WPA2 devices keep working)](pi5-hotspot-wpa3.md) |
| 5 | [Travel VPN: WireGuard client mode for Starlink and public Wi-Fi, with a kill switch and security hardening](travel-vpn/README.md) |
| 5a | [Connecting to Starlink: join the Starlink Mini's Wi-Fi, profile name vs. Wi-Fi name, fallback to home Wi-Fi](connect-to-starlink/README.md) |
| 6 | [Startup checklist: confirm everything is running after each power-up](travel-vpn/STARTUP-CHECKLIST.md) |
| 7 | [NVMe boot and a backup router: run from an SSD, keep a spare microSD and a second Pi ready](nvme-boot-and-backup.md) |
| Alt | [WireGuard home server: connect back to a Pi that stays at home](wireguard/README.md) |

---

## Pi-hole: Blocking Ads and Malicious Domains

Network-wide ad, tracker, and malware blocking for every device on your private Wi-Fi.

### ⚠️ Know this first: Pi-hole blocks domains, not hackers

Pi-hole is a DNS filter. It stops your devices from **reaching** bad places on the internet:

- ✅ Phishing sites
- ✅ Malware downloads
- ✅ Malware "call-home" (command-and-control) servers
- ✅ Ads and trackers

It does **not** stop someone from attacking your network directly. For that you still need:

- 🔥 A firewall
- 🔄 Router firmware updates
- 🔒 Closed ports (no unnecessary port forwarding)

#### Other hardening steps

- **Change the router's admin password** from the default, and use WPA3 (or WPA2/WPA3 transition mode, see [step 4](pi5-hotspot-wpa3.md)) with a strong Wi-Fi password.
- **Turn off UPnP and WPS** on your router. UPnP lets devices open ports on their own, which undoes "closed ports."
- **Keep every device updated**: computers, phones, cameras, smart TVs, not just the router.
- **Never expose your Pi-hole to the internet.** Don't forward port 53 to it. It should only answer devices inside your home network.
- **Use unique passwords and two-factor authentication** for important accounts.

---

### Recommended blocklists

Don't stack lots of overlapping ad lists. It slows gravity updates and causes more false positives. A clean setup is **one ad list plus one or two security lists**.

#### Ads and trackers (pick ONE)

| List | Notes | URL |
|---|---|---|
| **HaGeZi Multi Pro** | Most popular choice right now; tiers from Light to Pro++. Pro is the sweet spot. | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt` |
| **StevenBlack Unified Hosts** | Pi-hole's long-standing default. Covers ads and malware. | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| **OISD Big** | Large, well maintained, very few false positives. | Get the Pi-hole format link from [oisd.nl](https://oisd.nl) |
| **AdGuard DNS filter** | Solid, conservative option. | `https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt` |

#### Malware, phishing, and scams

| List | Notes | URL |
|---|---|---|
| **HaGeZi Threat Intelligence Feeds (TIF)** | Strongest single security list. Use the Medium version on lower-powered Pis. | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/tif.txt` |
| **URLhaus (abuse.ch)** | Active malware distribution domains. | `https://urlhaus.abuse.ch/downloads/hostfile/` |
| **Phishing Army (extended)** | Phishing domains. | `https://phishing.army/download/phishing_army_blocklist_extended.txt` |

Want more? [The Firebog](https://firebog.net/) keeps a curated directory. Its green-ticked lists are the ones considered safe for general use.

#### Example setup

1. **HaGeZi Pro**: ads, tracking, telemetry
2. **HaGeZi TIF Medium**: malware, phishing, scams
3. **URLhaus**: extra malware coverage (optional)

---

### Adding a blocklist (Pi-hole v6)

1. Open the Pi-hole web interface.
2. Go to **Lists**.
3. Paste the list URL, add an optional comment, and click **Add**.
4. Update gravity, either from **Tools → Update Gravity** in the web interface or from the command line:

   ```bash
   pihole -g
   ```

---

### Limits to be aware of

- **YouTube ads** usually can't be blocked by Pi-hole, because YouTube serves ads from the same domains as its videos.
- If a site or app breaks, check the Pi-hole **Query Log** and add the blocked domain to your **allowlist**.

---

## Next: WireGuard VPN

Take your Pi-hole with you. There are two versions, depending on where the Pi lives:

- **[Travel VPN](travel-vpn/README.md)** (the Pi travels with you): every device on your private Wi-Fi goes through an encrypted WireGuard tunnel to a VPN provider or your home, with a kill switch so nothing leaks if the tunnel drops. Works on Starlink, because it only connects *out* and opens no ports.
- **[Home server](wireguard/README.md)** (the Pi stays at home): your phone or laptop connects back to it from anywhere. It needs exactly one forwarded port (UDP 51820), which fits the "no unnecessary port forwarding" rule above, but it won't work behind CGNAT.

---

## Videos

- **Part 1 of 2**: Setting up Pi-hole: https://youtu.be/I8HdF6vV1IE
- **Part 2 of 2**: https://youtu.be/LijS5LekkVc
