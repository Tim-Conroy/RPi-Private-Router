# NVMe boot and a backup router

Run the travel router from an NVMe SSD (on a Raspberry Pi M.2 HAT+) instead of the microSD card, keep the microSD card as an up-to-date spare, and have a second Raspberry Pi 5 ready if the main one fails.

**Why bother:** NVMe is many times faster than microSD and far less likely to fail, especially after the sudden power cuts that happen with RV and Starlink setups.

The tool is **rpi-clone** ([Jeff Geerling's maintained version](https://rpi-clone.jeffgeerling.com/)), run on the Pi itself.

---

## 1. Install rpi-clone

```bash
curl https://raw.githubusercontent.com/geerlingguy/rpi-clone/master/install | sudo bash
```

## 2. Check the NVMe drive

```bash
lsblk
lsblk -f /dev/nvme0n1
```

Your microSD card is `mmcblk0`; the NVMe is `nvme0n1`. **Cloning erases everything on the NVMe.** If it shows `bootfs` and `rootfs` partitions, there's an older Raspberry Pi OS install on it. Look inside read-only before wiping it:

```bash
sudo mkdir -p /mnt/nvme
sudo mount -o ro /dev/nvme0n1p2 /mnt/nvme
cat /mnt/nvme/etc/hostname
sudo du -sh /mnt/nvme/home/*
cd ~ && sudo umount /mnt/nvme
```

`umount: target is busy`? Run `cd ~` first (your terminal may be inside the folder), and unmount the boot partition first if you mounted it.

## 3. Clone the microSD card to the NVMe

While booted from the microSD card:

```bash
sudo rpi-clone -f nvme0n1
```

`-f` wipes the drive and sets it up fresh. Check the destination says **`nvme0n1`** before answering `yes`. rpi-clone expands the copy to fill the drive.

## 4. Check the copy

```bash
lsblk -f /dev/nvme0n1                                  # nvme0n1p2 now fills the drive
sudo blkid -s PARTUUID /dev/mmcblk0p2 /dev/nvme0n1p2   # the two PARTUUIDs must differ

sudo mount -o ro /dev/nvme0n1p2 /mnt/nvme
sudo mount -o ro /dev/nvme0n1p1 /mnt/nvme/boot/firmware
grep -o 'root=[^ ]*' /mnt/nvme/boot/firmware/cmdline.txt   # must use the NVMe's PARTUUID
grep -v '^#' /mnt/nvme/etc/fstab                           # same
ls /mnt/nvme/etc/hostapd/hostapd.conf /mnt/nvme/etc/nftables.conf /mnt/nvme/usr/local/sbin/travel-vpn
cd ~ && sudo umount /mnt/nvme/boot/firmware /mnt/nvme
```

## 5. Boot from the NVMe first

Check the current boot order:

```bash
sudo rpi-eeprom-config | grep BOOT_ORDER
```

Read it **right to left**: `1` = microSD, `4` = USB, `6` = NVMe, `f` = start over. The common default `0xf461` tries the **microSD first**, so a Pi with a working microSD card never boots the NVMe.

Change it to NVMe first, microSD as the fallback:

```bash
sudo rpi-clone nvme0n1           # sync recent changes to the NVMe first
sudo rpi-eeprom-config --edit
```

Set the line to:

```
BOOT_ORDER=0xf416
```

Save (Ctrl+O, Enter), exit (Ctrl+X), then `sudo reboot`. Menu alternative: `sudo raspi-config` → **Advanced Options** → **Boot Order** → **NVMe/USB Boot**.

After the reboot, rejoin the private Wi-Fi on the Mac (it often switches back to your home Wi-Fi during the reboot), SSH in and check:

```bash
findmnt /                                  # /dev/nvme0n1p2
sudo rpi-eeprom-config | grep BOOT_ORDER   # 0xf416
sudo travel-vpn status
```

No `ssh-keygen -R` needed: the NVMe is an exact copy with the same SSH keys.

## 6. Keep the microSD card as an up-to-date spare

Leave it in the slot (it's the automatic fallback if the NVMe fails) and refresh it after any change, and about once a month:

```bash
sudo rpi-clone mmcblk0
```

This only works while booted from the NVMe; rpi-clone refuses to copy onto the disk it's running from. Later runs only copy what changed.

## 7. A backup Raspberry Pi 5

A second Pi 5 kept at home, used **only** if the main one fails.

**Never run both at the same time.** They'd broadcast the same Wi-Fi name, use the same address and fight over the same VPN key, so both tunnels keep dropping. Because only one runs at a time, the hostname, machine ID, SSH keys and VPN config can all stay the same.

**Set it up once:**

1. **Second Alfa adapter?** List both adapters so NetworkManager ignores whichever is plugged in. Get the backup Alfa's address on the backup Pi (`cat /sys/class/net/wlan1/address`), then on the main router:
   ```bash
   sudo tee /etc/NetworkManager/conf.d/99-unmanaged-alfa.conf > /dev/null <<'EOF'
   [keyfile]
   unmanaged-devices=mac:<main-alfa-mac>;mac:<backup-alfa-mac>
   EOF
   sudo systemctl reload NetworkManager
   sudo rpi-clone mmcblk0      # copy the change to the spare
   ```
   Moving the same Alfa between Pis? Skip this.
2. **Update the backup Pi's firmware** (booted from the spare microSD card):
   ```bash
   sudo rpi-eeprom-update -a
   sudo reboot
   ```
   A Pi 5 boots from microSD first by default, so no boot-order change is needed on the backup.

**Test it now, not when you need it:** shut down the main Pi (`sudo shutdown -h now`), move the microSD card (and the Alfa, if sharing) to the backup Pi, power it on, and run the [startup checklist](travel-vpn/STARTUP-CHECKLIST.md). Then shut it down and move everything back.

## Giving a clone to someone else, or running two routers at once

Then the copy needs its own identity and secrets: a new hostname, machine ID and SSH host keys; its own Wi-Fi name, password and subnet; **its own VPN config** (never share your Proton key); and your saved Wi-Fi passwords, login, SSH key, Pi-hole password and history removed. A script for this is planned.
