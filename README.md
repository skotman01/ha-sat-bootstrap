# Home Assistant Wyoming Satellite Bootstrap

This repository provides a **first-boot bootstrap system** for Home Assistant Wyoming voice satellites running on **Raspberry Pi OS Lite**.

It enables:

- Zero-touch provisioning of new satellites
- Per-device configuration based on **MAC address**
- Consistent service management via **systemd**
- A clean **golden image** cloning workflow

Once a golden image is prepared, **new satellites require no manual setup** beyond inserting the SD card and powering on.

---

## Quick Start

### 1) Prepare the golden image (do once)

On your “golden” Raspberry Pi OS Lite satellite (the one you will clone):

1. Ensure these are working:
   - `ha-satellite.service` (main runtime service)
   - `ha-satellite-firstboot.service` (one-time bootstrap, **enabled** but not currently running)
   - Wyoming Satellite code at `/opt/wyoming-satellite`
   - Service user `ha-sat` is in the `audio` group
2. Before imaging/cloning the SD card, reset identity so each clone is unique:

```bash
sudo systemctl stop ha-satellite.service

# Reset identity (MANDATORY)
sudo rm -f /etc/ssh/ssh_host_*
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

sudo poweroff
```

Now image/clone the SD card.

---

### 2) Add a new satellite (repeat per device)

1. Find the new Pi’s MAC address (from your router/DHCP leases, a sticker, or `ip link` once booted).
2. Create an inventory file:

```
inventory/<mac>.env
```

Example:

```
inventory/2c:cf:67:b1:ad:03.env
```

3. Fill it with device-specific settings (hostname, name, ports, audio device IDs):

```bash
SAT_HOSTNAME=ha-satellite-09
SAT_NAME=ha-satellite-09
SAT_URI=tcp://0.0.0.0:10700
SAT_EVENT_URI=tcp://127.0.0.1:10500
SAT_MIC_COMMAND=arecord -D plughw:CARD=seeed2micvoicec,DEV=0 -r 16000 -c 1 -f S16_LE -t raw
SAT_SND_COMMAND=aplay  -D plughw:CARD=seeed2micvoicec,DEV=0 -r 22050 -c 1 -f S16_LE -t raw
```

4. Boot the cloned SD card in the new Pi.

On first boot, the bootstrap will:
- detect MAC
- pull this repo to `/opt/ha-sat-bootstrap`
- write `/etc/ha-satellite/satellite.env`
- set hostname
- install & enable `ha-satellite.service`
- disable firstboot forever

---

### 3) Verify

```bash
systemctl status ha-satellite.service
journalctl -u ha-satellite.service -f
cat /var/log/ha-satellite-firstboot.log
```

---

## Diagram

```text
                 (Golden image SD)
                        |
                        | clone/image
                        v
                +------------------+
                | New Raspberry Pi |
                +------------------+
                        |
                        | Boot #1
                        v
       +------------------------------------+
       | ha-satellite-firstboot.service     |
       |  Exec: /usr/local/sbin/...sh       |
       +------------------------------------+
                        |
                        | 1) Detect MAC
                        | 2) git clone -> /opt/ha-sat-bootstrap
                        | 3) inventory/<mac>.env (or template)
                        | 4) write /etc/ha-satellite/satellite.env
                        | 5) set hostname
                        | 6) install+enable ha-satellite.service
                        | 7) disable firstboot
                        v
       +------------------------------------+
       | ha-satellite.service (runtime)     |
       |  User: ha-sat                      |
       |  Exec: /opt/wyoming-satellite/...  |
       +------------------------------------+
                        |
                        v
               Home Assistant Assist / HA
```

---


This repository provides a **first-boot bootstrap system** for Home Assistant Wyoming voice satellites running on **Raspberry Pi OS Lite**.

It enables:

- Zero-touch provisioning of new satellites
- Per-device configuration based on **MAC address**
- Consistent service management via **systemd**
- A clean **golden image** cloning workflow

Once a golden image is prepared, **new satellites require no manual setup** beyond inserting the SD card and powering on.

---

## Architecture Overview

### High-level flow

1. A Raspberry Pi boots from a **golden image**
2. A one-time systemd service runs:
   - Detects the Pi’s MAC address
   - Clones this repository
   - Selects the correct per-device config
   - Installs and enables the satellite service
3. The bootstrap disables itself permanently
4. The satellite runs normally on every subsequent boot

---

## Repository Structure

```
ha-sat-bootstrap/
├── firstboot/
│   ├── ha-satellite-firstboot.sh
│   └── ha-satellite-firstboot.service
├── systemd/
│   └── ha-satellite.service
├── templates/
│   └── satellite.env.example
├── inventory/
│   └── <mac>.env
└── README.md
```

---

## Golden Image Responsibilities

The **golden image** contains:

- `/usr/local/sbin/ha-satellite-firstboot.sh`
- `/etc/systemd/system/ha-satellite-firstboot.service` (enabled)
- A working Wyoming Satellite install at `/opt/wyoming-satellite`
- A dedicated service account: `ha-sat` (member of `audio`)
- Any required hardware support services (e.g. `2mic_leds.service`)

⚠️ The golden image **must not contain per-device identity**.

---

## Per-Device Configuration (MAC-based)

Each satellite is identified by the MAC address of its primary network interface.

### Inventory filename format

```
inventory/<mac>.env
```

Example:

```
inventory/2c:cf:67:b1:ad:03.env
```

---

## Inventory file example

```bash
SAT_HOSTNAME=ha-satellite-09
SAT_NAME=ha-satellite-09

SAT_URI=tcp://0.0.0.0:10700
SAT_EVENT_URI=tcp://127.0.0.1:10500

SAT_MIC_COMMAND=arecord -D plughw:CARD=seeed2micvoicec,DEV=0 -r 16000 -c 1 -f S16_LE -t raw
SAT_SND_COMMAND=aplay -D plughw:CARD=seeed2micvoicec,DEV=0 -r 22050 -c 1 -f S16_LE -t raw
```

---

## Template Configuration

`templates/satellite.env.example` is used **only if no inventory file matches the device MAC**.

```bash
# Fallback defaults – overridden by inventory/<mac>.env
SAT_HOSTNAME=ha-satellite
SAT_NAME=ha-satellite

SAT_URI=tcp://0.0.0.0:10700
SAT_EVENT_URI=tcp://127.0.0.1:10500

SAT_DEBUG=1

SAT_MIC_COMMAND=arecord -D plughw:CARD=seeed2micvoicec,DEV=0 -r 16000 -c 1 -f S16_LE -t raw
SAT_SND_COMMAND=aplay -D plughw:CARD=seeed2micvoicec,DEV=0 -r 22050 -c 1 -f S16_LE -t raw
```

---

## Firstboot Behavior

On **first boot only**, the system will:

1. Install prerequisites
2. Detect the active network interface MAC address
3. Clone this repository to `/opt/ha-sat-bootstrap`
4. Select the appropriate inventory or template config
5. Write runtime config to `/etc/ha-satellite/satellite.env`
6. Set the hostname (if defined)
7. Install and enable `ha-satellite.service`
8. Disable the firstboot service permanently

---

## Golden Image Preparation Checklist

```bash
# Stop runtime services
sudo systemctl stop ha-satellite.service
sudo systemctl stop ssh

# Reset identity
sudo rm -f /etc/ssh/ssh_host_*
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Re-assert boot policy
sudo systemctl enable ssh
sudo systemctl enable ssh-hostkey-bootstrap.service
sudo systemctl enable NetworkManager

# Optional hygiene
rm -f /home/scott/.bash_history
sudo rm -f /root/.bash_history

# Power off for imaging (do NOT reboot)
sudo poweroff

```

---

## Debugging

```bash
cat /var/log/ha-satellite-firstboot.log
systemctl status ha-satellite.service
journalctl -u ha-satellite.service -f
```
