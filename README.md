# Home Assistant Wyoming Satellite Bootstrap

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

ha-sat-bootstrap/
├── firstboot/
│ ├── ha-satellite-firstboot.sh # Source-of-truth firstboot script
│ └── ha-satellite-firstboot.service # Firstboot systemd unit (reference)
│
├── systemd/
│ └── ha-satellite.service # Main satellite service unit
│
├── templates/
│ └── satellite.env.example # Fallback defaults
│
├── inventory/
│ └── <mac>.env # Per-device configuration
│
└── README.md


---

## Golden Image Responsibilities

The **golden image** contains:

- `/usr/local/sbin/ha-satellite-firstboot.sh`
- `/etc/systemd/system/ha-satellite-firstboot.service` (enabled)
- A working Wyoming Satellite install at:
  - `/opt/wyoming-satellite`
- A dedicated service account:
  - `ha-sat` (member of `audio`)
- Any required hardware support services (for example: `2mic_leds.service`)

⚠️ The golden image **must not contain per-device identity**.

---

## Per-Device Configuration (MAC-based)

Each satellite is identified by the MAC address of its primary network interface.

### Inventory filename format

inventory/<mac>.env

Example:


Colon-separated MAC format is recommended.

---

### Inventory file example

```bash
SAT_HOSTNAME=ha-satellite-09
SAT_NAME=ha-satellite-09

SAT_URI=tcp://0.0.0.0:10700
SAT_EVENT_URI=tcp://127.0.0.1:10500

SAT_MIC_COMMAND=arecord -D plughw:CARD=seeed2micvoicec,DEV=0 -r 16000 -c 1 -f S16_LE -t raw
SAT_SND_COMMAND=aplay -D plughw:CARD=seeed2micvoicec,DEV=0 -r 22050 -c 1 -f S16_LE -t raw
```

## Template Configuration

templates/satellite.env.example is used only if no inventory file matches the device MAC.

It should be intentionally generic and obviously a fallback:

```
# Fallback defaults – overridden by inventory/<mac>.env

SAT_HOSTNAME=ha-satellite
SAT_NAME=ha-satellite

SAT_URI=tcp://0.0.0.0:10700
SAT_EVENT_URI=tcp://127.0.0.1:10500

SAT_DEBUG=1

SAT_MIC_COMMAND=arecord -D plughw:CARD=seeed2micvoicec,DEV=0 -r 16000 -c 1 -f S16_LE -t raw
SAT_SND_COMMAND=aplay -D plughw:CARD=seeed2micvoicec,DEV=0 -r 22050 -c 1 -f S16_LE -t raw
```

If a satellite boots using the template, it indicates that:

the MAC address was not registered, or
the inventory filename is incorrect

Firstboot Behavior

On first boot only, the system will:
1. Install prerequisites
2. Detect the active network interface MAC address
3. Clone this repository to: /opt/ha-sat-bootstrap
4. Select one of:
    # inventory/<mac>.env
    # templates/satellite.env.example
5. Write runtime config to: /etc/ha-satellite/satellite.env
6. Set the system hostname (if SAT_HOSTNAME is defined)
7. Install and enable: ha-satellite.service
8. Disable and remove the firstboot service permanently

Main Satellite Service
 - Service name: ha-satellite.service
 - Runs as user: ha-sat
 - Executable:
 - - /opt/wyoming-satellite/script/run
- Configuration source:
- - /etc/ha-satellite/satellite.env
- Starts after network and optional LED services

Golden Image Preparation Checklist

Before cloning a Pi to create new satellites:

```
# Stop satellite service
sudo systemctl stop ha-satellite.service

# Reset system identity (MANDATORY)
sudo rm -f /etc/ssh/ssh_host_*
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Optional home directory cleanup
rm -f /home/scott/.ssh/known_hosts
rm -rf /home/scott/.cache/*
rm -f /home/scott/.bash_history

# Power off before imaging
sudo poweroff
```

## Adding a New Satellite

- Create a new inventory file: inventory/<new-mac>.env
- Clone the golden image to a new SD card
- Insert the card into a Raspberry Pi
- Power on

The satellite will self-configure automatically.

## Debugging

Firstboot log:
- cat /var/log/ha-satellite-firstboot.log

Satellite service logs:
- systemctl status ha-satellite.service
- journalctl -u ha-satellite.service -f

## Design Philosophy

- Templates are intentionally generic
- Inventory files define identity
- Golden images are immutable
- Firstboot runs once, then disappears
- Runtime services should be boring and predictable