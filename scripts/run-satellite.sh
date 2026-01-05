#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/ha-satellite/satellite.env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

# Defaults (can be overridden in satellite.env)
SAT_DEBUG="${SAT_DEBUG:-1}"
SAT_NAME="${SAT_NAME:-ha-satellite}"
SAT_URI="${SAT_URI:-tcp://0.0.0.0:10700}"
SAT_MIC_COMMAND="${SAT_MIC_COMMAND:-arecord -r 16000 -c 1 -f S16_LE -t raw}"
SAT_SND_COMMAND="${SAT_SND_COMMAND:-aplay -r 22050 -c 1 -f S16_LE -t raw}"

# Where your "script/run" lives.
# If your repo contains script/run, this should be correct:
RUNNER="/opt/ha-sat-bootstrap/script/run"

if [[ ! -x "$RUNNER" ]]; then
  echo "ERROR: runner not found/executable: $RUNNER" >&2
  echo "Fix RUNNER path or ensure repo was cloned to /opt/ha-sat-bootstrap" >&2
  exit 2
fi

ARGS=()
if [[ "$SAT_DEBUG" == "1" || "$SAT_DEBUG" == "true" ]]; then
  ARGS+=(--debug)
fi

# Build arguments safely
ARGS+=(--name "$SAT_NAME")
ARGS+=(--uri "$SAT_URI")
ARGS+=(--mic-command "$SAT_MIC_COMMAND")
ARGS+=(--snd-command "$SAT_SND_COMMAND")

exec "$RUNNER" "${ARGS[@]}"
