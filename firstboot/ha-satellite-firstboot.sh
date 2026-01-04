#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ha-satellite-firstboot.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== HA Satellite Firstboot: $(date -Is) ==="

# ---- EDIT THESE ----
REPO_URL="https://git.scottheath.com/deploy/ha-sat-bootstrap"
REPO_BRANCH="main"
TARGET_DIR="/opt/ha-sat-bootstrap"

# Where this repo stores envs/templates
INVENTORY_DIR="inventory"
TEMPLATE_ENV="templates/satellite.env.example"

# Where runtime config should live on the satellite
RUNTIME_DIR="/etc/ha-satellite"
RUNTIME_ENV="${RUNTIME_DIR}/satellite.env"
# --------------------

need_root() { [[ "$(id -u)" -eq 0 ]] || { echo "Run as root"; exit 1; }; }
need_root

echo "[1/7] Ensure prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git rsync ca-certificates

echo "[2/7] Determine MAC address (prefer default route interface)"
DEFAULT_IF="$(ip route show default 0.0.0.0/0 2>/dev/null | awk '{print $5}' | head -n1 || true)"
if [[ -z "${DEFAULT_IF}" ]]; then
  DEFAULT_IF="$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|docker|veth' | head -n1 || true)"
fi

MAC=""
if [[ -n "${DEFAULT_IF}" && -e "/sys/class/net/${DEFAULT_IF}/address" ]]; then
  MAC="$(cat "/sys/class/net/${DEFAULT_IF}/address" | tr '[:upper:]' '[:lower:]' | tr -d '\n' || true)"
fi

if [[ -z "${MAC}" ]]; then
  echo "WARN: Could not determine MAC; using 'unknown'"
  MAC="unknown"
fi

echo "Default IF: ${DEFAULT_IF:-unknown}"
echo "MAC:        $MAC"

echo "[3/7] Clone or update repo"
if [[ -d "${TARGET_DIR}/.git" ]]; then
  git -C "$TARGET_DIR" fetch --all
  git -C "$TARGET_DIR" checkout "$REPO_BRANCH"
  git -C "$TARGET_DIR" pull --ff-only
else
  mkdir -p "$(dirname "$TARGET_DIR")"
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

echo "[4/7] Apply per-device env from inventory/<mac>.env (colon-formatted)"
mkdir -p "$RUNTIME_DIR"

INV_PATH="${TARGET_DIR}/${INVENTORY_DIR}/${MAC}.env"
TPL_PATH="${TARGET_DIR}/${TEMPLATE_ENV}"

if [[ -f "$INV_PATH" ]]; then
  echo "Using inventory env: $INV_PATH"
  install -m 0644 "$INV_PATH" "$RUNTIME_ENV"
elif [[ -f "$TPL_PATH" ]]; then
  echo "Using template env:  $TPL_PATH"
  install -m 0644 "$TPL_PATH" "$RUNTIME_ENV"
else
  echo "ERROR: No inventory env or template env found."
  echo "  Tried: $INV_PATH"
  echo "  Tried: $TPL_PATH"
  exit 2
fi

echo "[5/7] Optional: set hostname if SAT_HOSTNAME is in env"
# If you put SAT_HOSTNAME=ha-satellite09 in the env file, we’ll apply it.
set +u
source "$RUNTIME_ENV" || true
set -u
if [[ -n "${SAT_HOSTNAME:-}" ]]; then
  echo "Setting hostname to: $SAT_HOSTNAME"
  hostnamectl set-hostname "$SAT_HOSTNAME"
fi

echo "[6/7] Optional: install your main satellite service (if you add it later)"
# If you later put a unit file at: systemd/ha-satellite.service, we’ll install it.
MAIN_UNIT_SRC="${TARGET_DIR}/systemd/ha-satellite.service"
if [[ -f "$MAIN_UNIT_SRC" ]]; then
  cp "$MAIN_UNIT_SRC" /etc/systemd/system/ha-satellite.service
  systemctl daemon-reload
  systemctl enable ha-satellite.service
  systemctl restart ha-satellite.service || true
else
  echo "NOTE: No ${MAIN_UNIT_SRC} found; skipping main service install."
fi

echo "[7/7] Disable firstboot (one-time run)"
systemctl disable ha-satellite-firstboot.service || true
rm -f /etc/systemd/system/ha-satellite-firstboot.service || true
systemctl daemon-reload || true

echo "=== Firstboot complete: $(date -Is) ==="
