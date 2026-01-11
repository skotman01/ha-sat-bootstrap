# Home Assistant Wyoming Satellite Bootstrap

This repository provides a **first-boot bootstrap system** for Home Assistant Wyoming voice satellites running on **Raspberry Pi OS Lite**.

It is designed around a **golden image cloning workflow** with **zero-touch provisioning** for new satellites, while keeping **per-device identity out of Git**.

Once a golden image is prepared, **new satellites require no manual setup** beyond inserting the SD card, optionally editing a single file on the boot partition, and powering on.

---

## What This Provides

- One-time **first-boot provisioning** via systemd
- **Zero-touch** satellite initialization
- A **single unified runtime environment file**
- Deterministic hostname + MQTT identity
- Clean separation between:
  - *golden image state*
  - *per-device identity*
- A safe, repeatable **re-image / recovery path**

---

## Core Design Principles

- **Single source of truth**
  - Runtime config: `/etc/ha-satellite/satellite.env`
  - Identity variable: `SAT_HOSTNAME`
- **No identity in Git**
  - Hostnames, MACs, credentials are never committed
- **Idempotent**
  - Firstboot may safely re-run after re-imaging
- **Clone-safe**
  - Golden image contains no per-device state
- **Systemd-native**
  - No login-time scripts or ad-hoc init logic

---

## Clone vs Fork

Most users should **clone** this repository directly:

```bash
git clone https://www.github.com/skotman01/ha-sat-bootstrap.git
```

Fork this repository **only if** you plan to:
- modify bootstrap behavior
- support alternate hardware
- contribute changes upstream

---

## Quick Start

### 1) Prepare the Golden Image (do once)

On the Raspberry Pi that will become your **golden image**:

#### Prerequisites
Ensure the following already work **before imaging**:
- `ha-satellite-mq-agent.service`
- `assist-volume-restore.service`
- `ha-satellite-firstboot.service` (enabled, not currently running)
- Wyoming Satellite installed and functional
- Service user is a member of the `audio` group

#### Reset identity (mandatory)
Before capturing the SD card image:

# How to Reset Identity (Required)

Use the provided script from this repository:

```bash
sudo scripts/golden_image_prep.sh
```

This script:
- Stops runtime services
- Removes SSH host keys
- Resets `machine-id`
- Leaves configuration intact
- Prepares the system for safe cloning

When the script completes, it prints clear next steps:

- **Reboot** — re-run firstboot and validate configuration  
- **Shutdown** — power off and capture the SD card (**do not reboot before imaging**)

---

### 2) Add a New Satellite (repeat per device)

Per-device configuration is provided **locally**, not via Git.

#### Option A: Configure via boot partition (recommended)

1. Mount the SD card’s **boot** partition on your computer
2. Create a file:

```
/boot/ha-satellite.env
```

Example:

```bash
SAT_HOSTNAME=ha-satellite-kitchen

MQTT_HOST=192.168.1.10
MQTT_PORT=1883
MQTT_USER=
MQTT_PASS=
MQTT_BASE_TOPIC=ha/satellite
```

3. Insert the SD card and power on the Pi

#### Option B: No config file (fallback)

If no `/boot/ha-satellite.env` is present, firstboot will fall back to a template.
This is suitable only for testing.

---

### 3) What Happens on First Boot

On **first boot only**, the system will:

1. Detect the active network interface
2. Clone this repository to `/opt/ha-sat-bootstrap`
3. Read `/boot/ha-satellite.env` (if present)
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
├── scripts/
│   └── golden-image-prep.sh
├── INSTALL.md
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
SAT_HOSTNAME=ha-satellite-kitchen

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
- SSH host keys
- Machine IDs
- Network identity

---

## Golden Image Prep Script

A helper script is provided to reset identity safely:

```bash
sudo scripts/golden-image-prep.sh
```

At completion, the script prints clear next steps:

- **Reboot** to re-apply firstboot and validate
- **Shutdown** to capture the SD card image

---

## Audio Notes (WM8960 / Assist)

- Hardware: Seeed WM8960 2-Mic HAT (mono speaker)
- ALSA state is restored via `assist-volume-restore.service`
- Assist volume is controlled via ALSA `softvol`
- Wyoming Satellite must use `aplay -D default`

**Do not**:
- Use `hw:` or `plughw:` for playback
- Modify hardware gains after golden image capture

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
- Public-friendly
- Explicit by design

For build-from-scratch instructions, see **INSTALL.md**.
