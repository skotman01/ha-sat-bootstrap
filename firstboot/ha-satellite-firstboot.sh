#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ha-satellite-firstboot.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== HA Satellite Firstboot: $(date -Is) ==="

# ---- EDIT THESE ----
REPO_URL="https://git.scottheath.com/deploy/ha-sat-bootstrap"
REPO_BRANCH="main"
TARGET_DIR="/opt/ha-sat-bootstrap"

INVENTORY_DIR="inventory"
TEMPLATE_ENV="templates/satellite.env.example"

RUNTIME_DIR="/etc/ha-satellite"
RUNTIME_ENV="${RUNTIME_DIR}/satellite.env"
# --------------------

need_root() { [[ "$(id -u)" -eq 0 ]] || { echo "Run as root"; exit 1; }; }
need_root

echo "[1/8] Ensure prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git rsync ca-certificates

echo "[2/8] Determine MAC address (prefer default route interface)"
DEFAULT_IF="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1 || true)"

if [[ -z "${DEFAULT_IF}" ]]; then
  # fallback: pick first UP, non-loopback, non-virtual-ish interface
  DEFAULT_IF="$(ip -o link show up \
    | awk -F': ' '{print $2}' \
    | grep -vE '^(lo|docker|veth|br-|virbr|wg|zt|tailscale|sit|tun|tap)' \
    | head -n1 || true)"
fi

MAC=""
if [[ -n "${DEFAULT_IF}" && -e "/sys/class/net/${DEFAULT_IF}/address" ]]; then
  MAC="$(tr '[:upper:]' '[:lower:]' < "/sys/class/net/${DEFAULT_IF}/address" | tr -d '\n' || true)"
fi

if [[ -z "${MAC}" ]]; then
  echo "WARN: Could not determine MAC; using 'unknown'"
  MAC="unknown"
fi

MAC_NO_COLON="${MAC//:/}"

echo "Default IF: ${DEFAULT_IF:-unknown}"
echo "MAC:        $MAC"
echo "MAC (nc):   $MAC_NO_COLON"

echo "[3/8] Clone or update repo"
mkdir -p "$(dirname "$TARGET_DIR")"

if [[ -d "${TARGET_DIR}/.git" ]]; then
  git -C "$TARGET_DIR" fetch --all
  git -C "$TARGET_DIR" checkout "$REPO_BRANCH"
  git -C "$TARGET_DIR" pull --ff-only
else
  if ! git clone --branch "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR"; then
    echo "ERROR: Git clone failed (auth/DNS/network?). Repo: $REPO_URL"
    exit 3
  fi
fi

echo "[4/8] Apply per-device env from inventory/<mac>.env (supports colon + no-colon)"
mkdir -p "$RUNTIME_DIR"

INV_PATH_COLON="${TARGET_DIR}/${INVENTORY_DIR}/${MAC}.env"
INV_PATH_NC="${TARGET_DIR}/${INVENTORY_DIR}/${MAC_NO_COLON}.env"
TPL_PATH="${TARGET_DIR}/${TEMPLATE_ENV}"

if [[ -f "$INV_PATH_COLON" ]]; then
  echo "Using inventory env: $INV_PATH_COLON"
  install -m 0640 -o root -g root "$INV_PATH_COLON" "$RUNTIME_ENV"
elif [[ -f "$INV_PATH_NC" ]]; then
  echo "Using inventory env: $INV_PATH_NC"
  install -m 0640 -o root -g root "$INV_PATH_NC" "$RUNTIME_ENV"
elif [[ -f "$TPL_PATH" ]]; then
  echo "Using template env:  $TPL_PATH"
  install -m 0640 -o root -g root "$TPL_PATH" "$RUNTIME_ENV"
else
  echo "ERROR: No inventory env or template env found."
  echo "  Tried: $INV_PATH_COLON"
  echo "  Tried: $INV_PATH_NC"
  echo "  Tried: $TPL_PATH"
  exit 2
fi

echo "[5/8] Optional: set hostname if SAT_HOSTNAME is in env"
set +u
source "$RUNTIME_ENV" || true
set -u
if [[ -n "${SAT_HOSTNAME:-}" ]]; then
  echo "Setting hostname to: $SAT_HOSTNAME"
  hostnamectl set-hostname "$SAT_HOSTNAME"
fi

echo "[6/8] Optional: install your main satellite service (if present in repo)"
MAIN_UNIT_SRC="${TARGET_DIR}/systemd/ha-satellite.service"
if [[ -f "$MAIN_UNIT_SRC" ]]; then
  cp "$MAIN_UNIT_SRC" /etc/systemd/system/ha-satellite.service
  systemctl daemon-reload
  systemctl enable ha-satellite.service
  systemctl restart ha-satellite.service || true
else
  echo "NOTE: No ${MAIN_UNIT_SRC} found; skipping main service install."
fi

echo "[7/8] Disable firstboot (one-time run)"
# Prefer disabling the unit that invoked us
UNIT_TO_DISABLE="${SYSTEMD_UNIT:-ha-satellite-firstboot.service}"
systemctl disable "$UNIT_TO_DISABLE" || true
rm -f "/etc/systemd/system/$UNIT_TO_DISABLE" || true
systemctl daemon-reload || true

echo "[8/8] Done"
echo "=== Firstboot complete: $(date -Is) ==="
