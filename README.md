# Home Assistant Wyoming Satellite Bootstrap

This repository provides a **first-boot bootstrap system** for Home Assistant Wyoming voice satellites running on **Raspberry Pi OS Lite**.

It is designed around a **golden image cloning workflow** with **zero-touch provisioning** for new satellites.

Once a golden image is prepared, **new satellites require no manual setup** beyond inserting the SD card and powering on.

---

## What This Provides

- One-time **first-boot provisioning** via systemd  
- **MAC-based per-device inventory**  
- A **single unified runtime environment file**  
- Deterministic hostname + MQTT identity  
- Clean separation between:
  - *golden image state*
  - *per-device identity*
- A safe, repeatable **re-image / recovery path**

---

## Core Design Principles

- **Single source of truth**
  - One runtime env file: `/etc/ha-satellite/satellite.env`
  - One identity variable: `SAT_HOSTNAME`
- **Idempotent**
  - Firstboot can safely re-run after re-imaging
- **Clone-safe**
  - No per-device identity exists in the golden image
- **Systemd-native**
  - No ad-hoc init scripts or login-time hacks

---

## Quick Start

### 1) Prepare the Golden Image (do once)

On the Raspberry Pi that will become your **golden image**:

#### Prerequisites
Ensure the following already work **before** imaging:
- `ha-satellite-mq-agent.service`
- `assist-volume-restore.service`
- `ha-satellite-firstboot.service` (enabled, not currently running)
- Wyoming Satellite installed and functional
- Service user (`ha-sat` or root) is in the `audio` group

#### Reset identity (mandatory)
Before capturing the SD card image:

```bash
sudo systemctl stop ha-satellite-mq-agent.service

# Reset machine identity
sudo rm -f /etc/ssh/ssh_host_*
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Power off for imaging (do NOT reboot)
sudo poweroff
```

Now image or clone the SD card.

---

### 2) Add a New Satellite (repeat per device)

1. Boot the cloned SD card in a new Raspberry Pi.
2. Determine the device MAC address (router, DHCP leases, or `ip link`).
3. Create an inventory file:

```
inventory/<mac>.env
```

Example:
```
inventory/2c:cf:67:b1:ad:03.env
```

4. Define **only per-device identity and transport**:

```bash
# inventory/2c:cf:67:b1:ad:03.env
SAT_HOSTNAME=ha-satellite-09

MQTT_HOST=192.168.1.10
MQTT_PORT=1883
MQTT_USER=
MQTT_PASS=

MQTT_BASE_TOPIC=ha/satellite
```

5. Power on the device.

---

### 3) What Happens on First Boot

On **first boot only**, the system will:

1. Detect the active network interface MAC
2. Clone this repository to `/opt/ha-sat-bootstrap`
3. Select `inventory/<mac>.env` (or fallback template)
4. Write `/etc/ha-satellite/satellite.env`
5. Set the OS hostname from `SAT_HOSTNAME`
6. Enable required runtime services
7. Disable the firstboot service permanently

Subsequent boots skip all provisioning logic.

---

## Verification

After first boot:

```bash
hostname
cat /etc/hostname
grep -n '127.0.1.1' /etc/hosts
```

Services:
```bash
sudo systemctl status ha-satellite-mq-agent.service
sudo systemctl status assist-volume-restore.service
```

Logs:
```bash
journalctl -u ha-satellite-firstboot.service -b --no-pager
```

---

## Repository Structure

```
ha-sat-bootstrap/
├── firstboot/
│   ├── ha-satellite-firstboot.sh
│   └── ha-satellite-firstboot.service
├── systemd/
│   ├── ha-satellite-mq-agent.service
│   └── assist-volume-restore.service
├── templates/
│   └── satellite.env.example
├── inventory/
│   └── <mac>.env
├── scripts/
│   └── golden-image-prep.sh
└── README.md
```

---

## Runtime Environment File

The **only runtime config file** is:

```
/etc/ha-satellite/satellite.env
```

It contains:
- `SAT_HOSTNAME`
- MQTT connection details

Example:
```bash
SAT_HOSTNAME=ha-satellite-09

MQTT_HOST=192.168.1.10
MQTT_PORT=1883
MQTT_USER=
MQTT_PASS=
MQTT_BASE_TOPIC=ha/satellite
```

All services consume this file via `EnvironmentFile=`.

---

## Golden Image Responsibilities

The golden image **must contain**:
- Firstboot script + systemd unit (enabled)
- Working Wyoming Satellite install
- MQTT agent + volume restore services
- Audio stack fully validated

The golden image **must not contain**:
- Host-specific identity
- SSH keys
- Machine IDs
- Network identity

---

## Golden Image Preparation Script

A helper script is provided to safely reset identity:

```bash
sudo scripts/golden-image-prep.sh
sudo reboot
```

This ensures:
- Firstboot logic re-runs cleanly
- Hostname + env are re-applied
- Services restart in a known-good order

---

## Audio Notes (WM8960 / Assist)

- Hardware: Seeed WM8960 2-Mic HAT (mono speaker)
- ALSA mixer state is restored via `assist-volume-restore.service`
- Assist volume is controlled via ALSA `softvol`
- Wyoming Satellite must use `aplay -D default`

**Do not**:
- Use `hw:` or `plughw:` for playback
- Modify hardware gain after golden image capture

---

## Debugging

```bash
cat /var/log/ha-satellite-firstboot.log
journalctl -u ha-satellite-mq-agent.service -b
journalctl -u assist-volume-restore.service -b
```

---

## Status

This repository represents **v1** of the bootstrap system:
- Stable
- Clone-safe
- Recoverable
- Explicit by design

Future iterations may add:
- Pre-capture validation
- Self-test commands
- Optional Home Assistant discovery
