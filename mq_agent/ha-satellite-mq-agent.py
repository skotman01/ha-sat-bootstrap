#!/usr/bin/env python3
import json
import os
import socket
import subprocess
import sys
import time

import paho.mqtt.client as mqtt


def hostname_short() -> str:
    return socket.gethostname().split(".")[0]


HOST = hostname_short()

MQTT_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER = os.getenv("MQTT_USER", "")
MQTT_PASS = os.getenv("MQTT_PASS", "")

MQTT_BASE = os.getenv("MQTT_BASE", "ha-satellite")

# ALSA settings
ALSA_CARD = os.getenv("ALSA_CARD", "1")
ALSA_CONTROL = os.getenv("ALSA_CONTROL", "Speaker Playback Volume")
VOL_MIN = int(os.getenv("VOL_MIN", "0"))
VOL_MAX = int(os.getenv("VOL_MAX", "255"))

# Behavior
PUBLISH_STATE = os.getenv("PUBLISH_STATE", "1") == "1"
RETAIN_STATE = os.getenv("RETAIN_STATE", "0") == "1"
QOS = int(os.getenv("MQTT_QOS", "0"))

TOPIC_DEVICE_SET = f"{MQTT_BASE}/{HOST}/set/volume"
TOPIC_ALL_SET = f"{MQTT_BASE}/all/set/volume"
TOPIC_STATE = f"{MQTT_BASE}/{HOST}/state/volume"


def log(msg: str) -> None:
    print(msg, flush=True)


def clamp(n: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, n))


def parse_volume(payload: bytes) -> int | None:
    """
    Accept:
      - "110"
      - {"value":110} or {"volume":110}
    """
    s = payload.decode("utf-8", errors="ignore").strip()
    if not s:
        return None

    # Try raw integer
    if s.isdigit():
        return int(s)

    # Try JSON
    try:
        obj = json.loads(s)
        if isinstance(obj, dict):
            if "volume" in obj and isinstance(obj["volume"], (int, float, str)):
                return int(float(obj["volume"]))
            if "value" in obj and isinstance(obj["value"], (int, float, str)):
                return int(float(obj["value"]))
    except Exception:
        return None

    return None


def set_alsa_volume(vol: int) -> bool:
    numid = os.getenv("ALSA_NUMID", "").strip()

    if numid:
        cmd = ["/usr/bin/amixer", "-c", str(ALSA_CARD), "cset", f"numid={numid}", str(vol)]
    else:
        # fallback to name-based control (less reliable)
        cmd = ["/usr/bin/amixer", "-c", str(ALSA_CARD), "cset", f"name={ALSA_CONTROL}", str(vol)]

    try:
        out = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if out.stdout.strip():
            log(out.stdout.strip())
        return True
    except subprocess.CalledProcessError as e:
        log(f"ERROR: amixer failed (exit {e.returncode}): {' '.join(cmd)}")
        if e.stdout:
            log(e.stdout.strip())
        return False
    except FileNotFoundError:
        log("ERROR: /usr/bin/amixer not found")
        return False


def on_connect(client: mqtt.Client, userdata, flags, reason_code, properties=None):
    log(f"Connected to MQTT {MQTT_HOST}:{MQTT_PORT} as {HOST} (reason={reason_code})")
    client.subscribe(TOPIC_DEVICE_SET, qos=QOS)
    client.subscribe(TOPIC_ALL_SET, qos=QOS)
    log(f"Subscribed: {TOPIC_DEVICE_SET}, {TOPIC_ALL_SET}")


def on_message(client: mqtt.Client, userdata, msg: mqtt.MQTTMessage):
    vol = parse_volume(msg.payload)
    if vol is None:
        log(f"Ignoring invalid payload on {msg.topic}: {msg.payload!r}")
        return

    vol = clamp(vol, VOL_MIN, VOL_MAX)
    ok = set_alsa_volume(vol)

    if ok:
        log(f"Set volume={vol} (topic={msg.topic})")
        if PUBLISH_STATE:
            client.publish(TOPIC_STATE, str(vol), qos=QOS, retain=RETAIN_STATE)


def main() -> int:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASS)

    client.on_connect = on_connect
    client.on_message = on_message

    # Robust reconnect
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    while True:
        try:
            client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
            client.loop_forever()
        except Exception as e:
            log(f"MQTT loop error: {e}. Reconnecting in 5s...")
            time.sleep(5)


if __name__ == "__main__":
    sys.exit(main())
