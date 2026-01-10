# Golden Image Identity Reset

Before capturing a Raspberry Pi SD card as a **golden image**, all per-device identity **must** be reset.
This repository provides a helper script to do this safely and consistently.

---

## Why This Matters

Cloning an SD card without resetting identity causes **multiple devices to share the same system identity**, which leads to subtle and hard-to-debug failures.

Specifically:

- **SSH host keys**
  - All clones appear to be the *same host*
  - SSH warnings, MITM alerts, and connection failures occur

- **machine-id**
  - systemd services may misbehave
  - D-Bus and journald can produce inconsistent behavior
  - Home Assistant integrations may treat multiple satellites as one

- **Hostname propagation**
  - Hostnames may not reapply correctly on first boot
  - MQTT topics and logs become ambiguous

Resetting identity ensures **every clone generates a unique identity on first boot**.

---

## How to Reset Identity (Required)

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

## Important Notes

- Always run this script **immediately before** capturing an image
- Never reboot between running the script and imaging unless validating
- This step is mandatory for clone-safe satellites

---

## Where This Is Used

This workflow is referenced by:
- `README.md` — Golden image preparation
- `INSTALL.md` — Build-from-scratch instructions
- `scripts/golden_image_prep.sh` — Source of truth

---

## Status

This document applies to **v1** of the Home Assistant Wyoming Satellite Bootstrap system.
