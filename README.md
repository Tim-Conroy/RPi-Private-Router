# Pi-hole: Blocking Ads and Malicious Domains

Network-wide ad, tracker, and malware blocking for your home network using [Pi-hole](https://pi-hole.net/).

> 📺 **New here?** Watch **Part 1 of 2** on my YouTube channel for the full setup: https://youtu.be/I8HdF6vV1IE

---

## ⚠️ Know this first: Pi-hole blocks domains, not hackers

Pi-hole is a DNS filter. It stops your devices from **reaching** bad places on the internet:

- ✅ Phishing sites
- ✅ Malware downloads
- ✅ Malware "call-home" (command-and-control) servers
- ✅ Ads and trackers

It does **not** stop someone from attacking your network directly. For that you still need:

- 🔥 A firewall
- 🔄 Router firmware updates
- 🔒 Closed ports (no unnecessary port forwarding)

### Other hardening steps

- **Change the router's admin password** from the default, and use WPA2 or WPA3 with a strong Wi-Fi password.
- **Turn off UPnP and WPS** on your router. UPnP lets devices open ports on their own, which undoes "closed ports."
- **Keep every device updated**: computers, phones, cameras, smart TVs, not just the router.
- **Never expose your Pi-hole to the internet.** Don't forward port 53 to it. It should only answer devices inside your home network.
- **Use unique passwords and two-factor authentication** for important accounts.

---

## Recommended blocklists

Don't stack lots of overlapping ad lists. It slows gravity updates and causes more false positives. A clean setup is **one ad list plus one or two security lists**.

### Ads and trackers (pick ONE)

| List | Notes | URL |
|---|---|---|
| **HaGeZi Multi Pro** | Most popular choice right now; tiers from Light to Pro++. Pro is the sweet spot. | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt` |
| **StevenBlack Unified Hosts** | Pi-hole's long-standing default. Covers ads and malware. | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| **OISD Big** | Large, well maintained, very few false positives. | Get the Pi-hole format link from [oisd.nl](https://oisd.nl) |
| **AdGuard DNS filter** | Solid, conservative option. | `https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt` |

### Malware, phishing, and scams

| List | Notes | URL |
|---|---|---|
| **HaGeZi Threat Intelligence Feeds (TIF)** | Strongest single security list. Use the Medium version on lower-powered Pis. | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/tif.txt` |
| **URLhaus (abuse.ch)** | Active malware distribution domains. | `https://urlhaus.abuse.ch/downloads/hostfile/` |
| **Phishing Army (extended)** | Phishing domains. | `https://phishing.army/download/phishing_army_blocklist_extended.txt` |

Want more? [The Firebog](https://firebog.net/) keeps a curated directory. Its green-ticked lists are the ones considered safe for general use.

### Example setup

1. **HaGeZi Pro**: ads, tracking, telemetry
2. **HaGeZi TIF Medium**: malware, phishing, scams
3. **URLhaus**: extra malware coverage (optional)

---

## Adding a blocklist (Pi-hole v6)

1. Open the Pi-hole web interface.
2. Go to **Lists**.
3. Paste the list URL, add an optional comment, and click **Add**.
4. Update gravity, either from **Tools → Update Gravity** in the web interface or from the command line:

   ```bash
   pihole -g
   ```

---

## Limits to be aware of

- **YouTube ads** usually can't be blocked by Pi-hole, because YouTube serves ads from the same domains as its videos.
- If a site or app breaks, check the Pi-hole **Query Log** and add the blocked domain to your **allowlist**.

---

## Next: WireGuard VPN

Take your Pi-hole with you. The **[WireGuard VPN guide](wireguard/README.md)** adds a secure tunnel back to your Raspberry Pi router, so your phone or laptop is protected on public Wi-Fi and keeps Pi-hole ad blocking away from home.

It includes ready-to-run scripts for the server setup and for adding devices with a QR code, plus an example nftables ruleset. The VPN needs exactly one forwarded port (UDP 51820), which fits the "no unnecessary port forwarding" rule above.

---

## Videos

- **Part 1 of 2**: Setting up Pi-hole: [YOUR PART 1 VIDEO LINK]
- **Part 2 of 2**: [YOUR PART 2 VIDEO LINK]
