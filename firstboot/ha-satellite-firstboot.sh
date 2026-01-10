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


echo "[4/10] Apply runtime env (prefer /boot, keep identity out of Git)"
mkdir -p "$RUNTIME_DIR"

# Public-friendly: user-editable config on the boot partition
BOOT_ENV="/boot/ha-satellite.env"

# Optional: local inventory stored on the device (not in Git)
LOCAL_INV_DIR="${RUNTIME_DIR}/inventory"
LOCAL_INV_COLON="${LOCAL_INV_DIR}/${MAC}.env"
LOCAL_INV_NC="${LOCAL_INV_DIR}/${MAC_NO_COLON}.env"

# Optional (dev-only): repo inventory (consider removing for public releases)
REPO_INV_COLON="${TARGET_DIR}/${INVENTORY_DIR}/${MAC}.env"
REPO_INV_NC="${TARGET_DIR}/${INVENTORY_DIR}/${MAC_NO_COLON}.env"

TPL_PATH="${TARGET_DIR}/${TEMPLATE_ENV}"

pick_env() {
  local src="$1"
  echo "Using env: $src"
  install -m 0640 -o root -g root "$src" "$RUNTIME_ENV"
  # Normalize line endings (CRLF → LF) so bash/systemd parse vars correctly
  sed -i 's/\r$//' "$RUNTIME_ENV" || true
}

if [[ -f "$BOOT_ENV" ]]; then
  pick_env "$BOOT_ENV"

elif [[ -f "$LOCAL_INV_COLON" ]]; then
  pick_env "$LOCAL_INV_COLON"
elif [[ -f "$LOCAL_INV_NC" ]]; then
  pick_env "$LOCAL_INV_NC"

elif [[ -f "$REPO_INV_COLON" ]]; then
  echo "NOTE: Using repo inventory (dev-only). Prefer /boot/ha-satellite.env for public usage."
  pick_env "$REPO_INV_COLON"
elif [[ -f "$REPO_INV_NC" ]]; then
  echo "NOTE: Using repo inventory (dev-only). Prefer /boot/ha-satellite.env for public usage."
  pick_env "$REPO_INV_NC"

elif [[ -f "$TPL_PATH" ]]; then
  pick_env "$TPL_PATH"

else
  echo "ERROR: No env found."
  echo "  Tried: $BOOT_ENV"
  echo "  Tried: $LOCAL_INV_COLON"
  echo "  Tried: $LOCAL_INV_NC"
  echo "  Tried: $REPO_INV_COLON"
  echo "  Tried: $REPO_INV_NC"
  echo "  Tried: $TPL_PATH"
  exit 2
fi


# Normalize line endings (CRLF → LF) so bash/systemd parse vars correctly
sed -i 's/\r$//' "$RUNTIME_ENV" || true

echo "[5/10] Setting hostname from SAT_HOSTNAME (single source of truth)"

# Normalize CRLF → LF
sed -i 's/\r$//' "$RUNTIME_ENV" || true

SAT_HOSTNAME="$(grep -m1 '^SAT_HOSTNAME=' "$RUNTIME_ENV" | cut -d= -f2- || true)"
SAT_HOSTNAME="$(printf '%s' "$SAT_HOSTNAME" | tr -d '\r" ')"

if [[ -z "$SAT_HOSTNAME" ]]; then
  echo "SAT_HOSTNAME not set; skipping hostname configuration"
fi

# Strict validation
if [[ ! "$SAT_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
  echo "ERROR: Invalid SAT_HOSTNAME='$SAT_HOSTNAME'"
  exit 1
fi

echo "Setting OS hostname to: $SAT_HOSTNAME"

hostnamectl set-hostname "$SAT_HOSTNAME"
echo "$SAT_HOSTNAME" > /etc/hostname

# Ensure sudo/systemd resolution works
if grep -qE '^\s*127\.0\.1\.1\s' /etc/hosts; then
  sed -i "s/^\s*127\.0\.1\.1\s.*/127.0.1.1\t$SAT_HOSTNAME/" /etc/hosts
else
  echo -e "127.0.1.1\t$SAT_HOSTNAME" >> /etc/hosts
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

echo "[6.7/10] Install/enable wyoming-openwakeword service (local wake word)"
OWW_UNIT_SRC="${TARGET_DIR}/systemd/wyoming-openwakeword.service"
if [[ -f "$OWW_UNIT_SRC" ]]; then
  cp "$OWW_UNIT_SRC" /etc/systemd/system/wyoming-openwakeword.service
  systemctl daemon-reload
  systemctl enable wyoming-openwakeword.service
  systemctl restart wyoming-openwakeword.service || true
else
  echo "NOTE: No $OWW_UNIT_SRC found; skipping wyoming-openwakeword install."
fi

echo "[6.8/10] Install/enable satellite MQTT agent"
AGENT_SCRIPT_SRC="${TARGET_DIR}/mq_agent/ha-satellite-mq-agent.py"
AGENT_UNIT_SRC="${TARGET_DIR}/systemd/ha-satellite-mq-agent.service"

if [[ -f "$AGENT_SCRIPT_SRC" && -f "$AGENT_UNIT_SRC" ]]; then
  install -m 0755 -o root -g root "$AGENT_SCRIPT_SRC" /usr/local/bin/ha-satellite-mq-agent.py
  cp "$AGENT_UNIT_SRC" /etc/systemd/system/ha-satellite-mq-agent.service

  systemctl daemon-reload
  systemctl enable ha-satellite-mq-agent.service
  systemctl restart ha-satellite-mq-agent.service || true
else
  echo "NOTE: satellite-mq-agent files missing; skipping install."
fi


echo "[7/10] Optional: install your main satellite service (if present in repo)"
MAIN_UNIT_SRC="${TARGET_DIR}/systemd/ha-satellite.service"
if [[ -f "$MAIN_UNIT_SRC" ]]; then
  cp "$MAIN_UNIT_SRC" /etc/systemd/system/ha-satellite.service
  systemctl daemon-reload
  systemctl enable ha-satellite.service
  systemctl start --no-block ha-satellite.service || true
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
