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

MARKER="${RUNTIME_DIR}/.provisioned"
if [[ -f "$MARKER" ]]; then
  echo "Marker exists ($MARKER); skipping firstboot."
  exit 0
fi

echo "[1/10] Ensure prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git rsync ca-certificates

echo "[2/10] Determine MAC address (prefer default route interface)"
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

echo "[3/10] Clone or update repo"

if [[ -d "${TARGET_DIR}/.git" ]]; then
  echo "Repo exists; resetting to ${REPO_BRANCH}"
  git -C "$TARGET_DIR" fetch --all
  git -C "$TARGET_DIR" reset --hard "origin/${REPO_BRANCH}"
  git -C "$TARGET_DIR" clean -fd
else
  mkdir -p "$(dirname "$TARGET_DIR")"
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR"
fi


echo "[4/10] Apply per-device env from inventory/<mac>.env (supports colon + no-colon)"
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

# Normalize line endings (CRLF → LF) so bash/systemd parse vars correctly
sed -i 's/\r$//' "$RUNTIME_ENV" || true
# Strip surrounding quotes on command vars if inventory/template included them
sed -i -E 's/^(SAT_(MIC_COMMAND|SND_COMMAND))="(.*)"$/\1=\3/' "$RUNTIME_ENV" || true



echo "[5/10] Optional: set hostname if SAT_HOSTNAME is in env"

# Load env vars from the file we just installed
set +u
source "$RUNTIME_ENV" || true
set -u

# If SAT_HOSTNAME exists but SAT_NAME doesn't, set SAT_NAME to match (once)
if [[ -n "${SAT_HOSTNAME:-}" && -z "${SAT_NAME:-}" ]]; then
  # escape '&' for sed replacement safety
  _hn_sed=${SAT_HOSTNAME//&/\\&}

  if grep -q '^SAT_NAME=' "$RUNTIME_ENV"; then
    sed -i "s|^SAT_NAME=.*|SAT_NAME=${_hn_sed}|" "$RUNTIME_ENV"
  else
    echo "SAT_NAME=${SAT_HOSTNAME}" >> "$RUNTIME_ENV"
  fi

  # Reload so the shell matches the file
  set +u
  source "$RUNTIME_ENV" || true
  set -u
fi

# Set OS hostname if provided
if [[ -n "${SAT_HOSTNAME:-}" ]]; then
  echo "Setting hostname to: $SAT_HOSTNAME"
  hostnamectl set-hostname "$SAT_HOSTNAME"
fi



echo "[6/10] Install/enable SSH hostkey bootstrap service"
SSH_BOOTSTRAP_SRC="${TARGET_DIR}/systemd/ssh-hostkey-bootstrap.service"
if [[ -f "$SSH_BOOTSTRAP_SRC" ]]; then
  cp "$SSH_BOOTSTRAP_SRC" /etc/systemd/system/ssh-hostkey-bootstrap.service
  systemctl daemon-reload
  systemctl enable ssh-hostkey-bootstrap.service
else
  echo "NOTE: No $SSH_BOOTSTRAP_SRC found; skipping ssh-hostkey-bootstrap install."
fi

echo "[6.5/10] Install system-wide ALSA config (asound.conf)"
ASOUND_SRC="${TARGET_DIR}/audio/asound.conf"
if [[ -f "$ASOUND_SRC" ]]; then
  install -m 0644 -o root -g root "$ASOUND_SRC" /etc/asound.conf
else
  echo "NOTE: No $ASOUND_SRC found; skipping /etc/asound.conf install."
fi

echo "[6.6/10] Install/enable Assist volume restore service (optional)"
ASSIST_VOL_UNIT_SRC="${TARGET_DIR}/systemd/assist-volume-restore.service"
if [[ -f "$ASSIST_VOL_UNIT_SRC" ]]; then
  cp "$ASSIST_VOL_UNIT_SRC" /etc/systemd/system/assist-volume-restore.service
  systemctl daemon-reload
  systemctl enable assist-volume-restore.service
  systemctl start assist-volume-restore.service || true
else
  echo "NOTE: No $ASSIST_VOL_UNIT_SRC found; skipping assist-volume-restore install."
fi

echo "[7/10] Optional: install your main satellite service (if present in repo)"
MAIN_UNIT_SRC="${TARGET_DIR}/systemd/ha-satellite.service"
if [[ -f "$MAIN_UNIT_SRC" ]]; then
  cp "$MAIN_UNIT_SRC" /etc/systemd/system/ha-satellite.service
  systemctl daemon-reload
  systemctl enable ha-satellite.service
  systemctl restart ha-satellite.service || true
  systemctl reset-failed ha-satellite.service || true

else
  echo "NOTE: No ${MAIN_UNIT_SRC} found; skipping main service install."
fi

echo "[8/10] Ensure SSH is enabled"
systemctl enable ssh || true
systemctl restart ssh || true


echo "[9/10] Mark provisioned"
touch "$MARKER"


echo "[10/10] Done"
echo "=== Firstboot complete: $(date -Is) ==="

echo "Installed ha-satellite.service ExecStart:"
systemctl cat ha-satellite.service | sed -n '1,120p'
