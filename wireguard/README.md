# WireGuard on a Raspberry Pi 5 router (Trixie + Pi-hole + nftables)

Assumes: Pi 5 on Raspberry Pi OS Trixie, already routing with hostapd + dnsmasq + nftables, Pi-hole installed.
Defaults: WAN `eth0`, LAN `wlan0`, VPN subnet `10.10.0.0/24`, port `51820/udp`. Change them in all three files if yours differ.

## 1. Install and start the server
```bash
cd wireguard
chmod +x wg-server-setup.sh wg-add-client.sh
sudo ./wg-server-setup.sh
```

## 2. Firewall
Merge the `### WG` lines from `nftables.conf` into your `/etc/nftables.conf`, then:
```bash
sudo nft -c -f /etc/nftables.conf      # syntax check, changes nothing
sudo systemctl restart nftables
```
Do this from a LAN device, not over SSH from the internet, in case of a typo.

## 3. Let Pi-hole answer VPN clients
Check Pi-hole's listening mode (Settings > DNS > Interface settings, or):
```bash
sudo pihole-FTL --config dns.listeningMode
```
- `LOCAL` (Allow only local requests): works, because `10.10.0.0/24` is a subnet directly attached to the Pi.
- `SINGLE` (Respond only on one interface): VPN clients get **no DNS**. Switch to `LOCAL`:
  `sudo pihole-FTL --config dns.listeningMode LOCAL`
- Avoid `ALL` unless your firewall blocks port 53 from the WAN (the ruleset above does).

Also confirm only one thing owns port 53: `sudo ss -lunp | grep ':53 '` should show `pihole-FTL`, not the standalone dnsmasq. If standalone dnsmasq is only doing DHCP, it needs `port=0` in its config.

## 4. Reach the Pi from the internet
1. **Check for CGNAT:** compare the WAN IP on your ISP router with what https://ifconfig.me shows. If they differ (or the router shows `100.64.x.x`–`100.127.x.x`), port forwarding won't work; use Tailscale instead.
2. **Port forward** UDP 51820 on the ISP router to the Pi's WAN-side IP.
3. **Dynamic DNS** with DuckDNS (free): create a subdomain, then add to root's crontab (`sudo crontab -e`):
   ```
   */5 * * * * curl -s "https://www.duckdns.org/update?domains=YOURNAME&token=YOURTOKEN&ip=" >/dev/null
   ```

## 5. Add a phone
```bash
sudo ./wg-add-client.sh phone yourname.duckdns.org
```
Scan the QR code in the WireGuard app. One client per device; don't share configs.

## 6. Test (the on-camera demo)
1. Turn off Wi-Fi on the phone (cellular only) and enable the tunnel.
2. On the Pi: `sudo wg show` → a recent "latest handshake" plus growing transfer counters.
3. Visit an ad-heavy site on the phone; watch Pi-hole's Query Log show requests from `10.10.0.2`.
4. Check https://ifconfig.me on the phone: it should show your home IP.

## Troubleshooting
| Symptom | Likely cause |
|---|---|
| No handshake | Port forward missing/wrong, CGNAT, wrong endpoint hostname, or the `udp dport 51820` rule missing |
| Handshake but no internet | Forward rule `wg0 -> eth0` or masquerade missing; `ip_forward` off |
| Internet works by IP but not names | Pi-hole listening mode is `SINGLE`, or DNS line in client config wrong |
| Works at home, not on cellular | Testing from inside the LAN; test on cellular with Wi-Fi off |
