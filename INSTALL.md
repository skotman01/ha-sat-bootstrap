# Installing Wyoming Satellite + OpenWakeWord + MQTT

This document describes how to build a **Home Assistant Wyoming voice satellite** from scratch using
**Raspberry Pi OS Lite**, **OpenWakeWord**, and **MQTT**, and then integrate it with the
`ha-sat-bootstrap` repository for zero-touch provisioning.

This guide is intended for **public / DIY users** who want to reproduce the environment used by this repo.

---

## Hardware Requirements

- Raspberry Pi (3B+, 4, or 5 recommended)
- MicroSD card (16GB+)
- Microphone + speaker
  - Tested: **Seeed WM8960 2-Mic HAT**
- Network connectivity (Ethernet or Wi-Fi)

### Tested with

- Raspberry Pi Zero W 2
- MicroCS Card (64GB)
- SEEED WM8960 2-Mic HAT
- WiFi

---

## Operating System

### Install Raspberry Pi OS Lite (64-bit recommended)

1. Use Raspberry Pi Imager
2. Choose:
   - **Raspberry Pi OS Lite (64-bit)**
3. Configure:
   - Enable SSH
   - Set locale / timezone
   - Set user + password
4. Flash and boot the Pi

Update the system:
```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

---

## Audio Setup (WM8960)

If using a Seeed WM8960-based HAT:

```bash
curl -fsSL https://github.com/Seeed-Studio/seeed-linux-dtoverlays/raw/master/scripts/reTerminal/install.sh | sudo bash
sudo reboot
```

Verify devices:
```bash
arecord -l
aplay -l
```

Ensure playback works using:
```bash
aplay -D default /usr/share/sounds/alsa/Front_Center.wav
```

---

## Install Wyoming Satellite

### System dependencies
```bash
sudo apt install -y   python3   python3-venv   python3-pip   sox   libasound2-dev   git
```

### Clone and install Wyoming Satellite
```bash
sudo mkdir -p /opt
sudo chown $USER:$USER /opt
cd /opt

git clone https://github.com/home-assistant/wyoming-satellite.git
cd wyoming-satellite

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Test it manually:
```bash
script/run   --name test-satellite   --mic-command "arecord -D default -r 16000 -c 1 -f S16_LE -t raw"   --snd-command "aplay -D default -r 22050 -c 1 -f S16_LE -t raw"
```

---

## Install OpenWakeWord

```bash
pip install openwakeword
```

Download models:
```bash
mkdir -p ~/.local/share/openwakeword
python3 -m openwakeword.download
```

Verify:
```bash
python3 - <<EOF
from openwakeword.model import Model
m = Model()
print(m.models)
EOF
```

---

## Install MQTT Broker (optional)

If you do not already have MQTT:

```bash
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable --now mosquitto
```

Test:
```bash
mosquitto_sub -t '#' -v
```

---

## Create Service User

```bash
sudo useradd -r -m -s /usr/sbin/nologin ha-sat
sudo usermod -aG audio ha-sat
```

---

## Fork this



## Install Bootstrap Repo

```bash
cd /opt
sudo git clone https://github.com/skotman01/ha-sat-bootstrap.git
sudo chown -R root:root /opt/ha-sat-bootstrap
```

Install firstboot components:
```bash
sudo cp firstboot/ha-satellite-firstboot.sh /usr/local/sbin/
sudo cp firstboot/ha-satellite-firstboot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ha-satellite-firstboot.service
```

---

## Create Inventory Entry

Determine MAC address:
```bash
ip link
```

Create inventory file:
```bash
cd /opt/ha-sat-bootstrap
sudo mkdir -p inventory
sudo nano inventory/<mac>.env
```

Example:
```bash
SAT_HOSTNAME=ha-satellite-01

MQTT_HOST=192.168.1.10
MQTT_PORT=1883
MQTT_BASE_TOPIC=ha/satellite
```

---

## First Boot Behavior

On next reboot:
- Bootstrap runs once
- Hostname is set
- `/etc/ha-satellite/satellite.env` is written
- MQTT + volume services are enabled
- Firstboot disables itself

Reboot:
```bash
sudo reboot
```

---

## Verify

```bash
hostname
systemctl status ha-satellite-mq-agent.service
journalctl -u ha-satellite-firstboot.service -b
```

---

## Home Assistant Configuration

In Home Assistant:
- Enable **MQTT integration**
- Subscribe to:
  ```text
  ha/satellite/+/status
  ha/satellite/+/volume
  ```
- Create automations or scripts to publish volume or control messages

---

## Notes

- This repo does **not** require Home Assistant OS
- All configuration is file-based and reproducible
- Re-imaging + reboot is the supported recovery path

---

## Troubleshooting

- **No audio**: verify `aplay -D default` works
- **Wake word not detected**: confirm OpenWakeWord models installed
- **MQTT not connecting**: verify broker IP + credentials

---

## Status

This document supports **v1** of the bootstrap system and is intended for
advanced users comfortable with Linux, systemd, and Home Assistant internals.
