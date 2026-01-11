# Home Assistant Integration (MQTT Volume Control)

This document describes how to integrate a **Wyoming Satellite** with Home Assistant
to provide **volume control and feedback** using MQTT.

This is intentionally separated from the main bootstrap README.

---

## What This Provides

- Native **volume slider** in Home Assistant
- Optional **volume feedback** from the satellite
- Works without a `media_player` entity
- Compatible with dashboards (Mushroom, Tile, etc.)

---

## Requirements

- Home Assistant with the **MQTT integration** enabled
- Satellite running the **MQTT agent**
- MQTT topics follow this pattern:

```
ha-satellite/<sat_hostname>/volume/set
ha-satellite/<sat_hostname>/volume/state
```

---

## Files

- `ha_volume.yaml`
  - YAML-only configuration
  - Safe to include via `!include` or packages

---

## Installation

### Option A: Packages (recommended)

Create a file:
```
packages/ha_satellite_volume.yaml
```

Paste the contents of `ha_volume.yaml` and adjust the hostname.

Enable packages in `configuration.yaml`:
```yaml
homeassistant:
  packages: !include_dir_named packages
```

Restart Home Assistant.

---

### Option B: Manual include

Split sections from `ha_volume.yaml` into:
- `mqtt:`
- `template:`
- `automation:`

Restart Home Assistant.

---

## Customization

### Volume range
If your agent uses a different range, update:
```yaml
min: 0
max: 255
```

And adjust the percent sensor math accordingly.

### Retained state
If your agent publishes retained state, Home Assistant will restore volume immediately after restart.

---

## UI Tips

- Add `number.*` entities directly to dashboards as sliders
- Add the percent sensor for a clean readout
- Works well with Mushroom sliders and Tiles

---

## Notes

- This intentionally avoids `media_player` entities
- Volume is controlled via ALSA on the satellite
- Hardware gain should be set in the golden image

---

## Status

This integration supports **v1** of the HA Satellite MQTT agent.
