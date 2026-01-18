#!/usr/bin/env bash
set -euo pipefail

# ---- Defaults (override via /etc/ha-satellite/mq_agent.env if you want) ----
REPO_DIR="${REPO_DIR:-/opt/ha-sat-bootstrap}"
BRANCH_DEFAULT="${BRANCH_DEFAULT:-main}"
STATUS_TOPIC_DEFAULT="${STATUS_TOPIC_DEFAULT:-ha-satellite/${HOSTNAME_SHORT:-unknown}/status}"
MQTT_HOST_DEFAULT="${MQTT_HOST_DEFAULT:-127.0.0.1}"
MQTT_PORT_DEFAULT="${MQTT_PORT_DEFAULT:-1883}"

LOCK_FILE="${LOCK_FILE:-/var/lock/ha-sat-update.lock}"

# Services to restart after update (edit to match your fleet)
RESTART_SERVICES=(
  "ha-satellite-mq-agent.service"
  # "wyoming-satellite.service"
  # "openwakeword.service"
)

log() { echo "[$(date -Is)] $*"; }

publish_status() {
  local state="$1" action="$2" msg="$3" extra="${4:-}"
  # Best-effort publish (won't fail the update if MQTT publish fails)
  if command -v mosquitto_pub >/dev/null 2>&1; then
    mosquitto_pub \
      -h "${MQTT_HOST:-$MQTT_HOST_DEFAULT}" \
      -p "${MQTT_PORT:-$MQTT_PORT_DEFAULT}" \
      -t "${STATUS_TOPIC:-$STATUS_TOPIC_DEFAULT}" \
      -q 1 -r \
      -m "{\"host\":\"${HOSTNAME_SHORT:-$(hostname -s)}\",\"state\":\"${state}\",\"action\":\"${action}\",\"msg\":\"${msg}\",\"ts\":\"$(date -Is)\"${extra}}}" \
      >/dev/null 2>&1 || true
  fi
}

# ---- Load env if present ----
# Keep per-host config out of repo
if [[ -f /etc/ha-satellite/mq_agent.env ]]; then
  # shellcheck disable=SC1091
  source /etc/ha-satellite/mq_agent.env
fi

HOSTNAME_SHORT="${HOSTNAME_SHORT:-$(hostname -s)}"
STATUS_TOPIC="${STATUS_TOPIC:-ha-satellite/${HOSTNAME_SHORT}/status}"

CMD="${1:-update}"
REF="${2:-$BRANCH_DEFAULT}"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another update is already running."
  publish_status "busy" "$CMD" "update already running"
  exit 0
fi

publish_status "running" "$CMD" "starting" ",\"ref\":\"${REF}\""

if [[ ! -d "$REPO_DIR/.git" ]]; then
  log "ERROR: Repo not found at $REPO_DIR"
  publish_status "error" "$CMD" "repo not found" ",\"ref\":\"${REF}\""
  exit 2
fi

cd "$REPO_DIR"

FROM="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
publish_status "running" "$CMD" "current revision" ",\"ref\":\"${REF}\",\"from\":\"${FROM}\""

log "Fetching..."
git fetch --all --tags --prune

log "Checking out ref: $REF"
# Allow either branch name (main) or tag (v1.2.3). Reject weird refs.
if [[ "$REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  git checkout -q "$REF"
else
  log "ERROR: Ref contains invalid characters"
  publish_status "error" "$CMD" "invalid ref" ",\"ref\":\"${REF}\""
  exit 3
fi

log "Pulling..."
# Pull only if it’s a branch; tags won't pull
if git symbolic-ref -q HEAD >/dev/null 2>&1; then
  git pull --ff-only
fi

TO="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
publish_status "running" "$CMD" "updated code" ",\"ref\":\"${REF}\",\"from\":\"${FROM}\",\"to\":\"${TO}\""

# Optional: reinstall systemd units from repo if you keep them there
if [[ -x "$REPO_DIR/scripts/install_units.sh" ]]; then
  log "Installing/refreshing unit files..."
  "$REPO_DIR/scripts/install_units.sh" || true
fi

log "Daemon reload..."
systemctl daemon-reload

log "Restarting services..."
for svc in "${RESTART_SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "^${svc}"; then
    systemctl restart "$svc" || true
  fi
done

publish_status "ok" "$CMD" "completed" ",\"ref\":\"${REF}\",\"from\":\"${FROM}\",\"to\":\"${TO}\""
log "Done."
