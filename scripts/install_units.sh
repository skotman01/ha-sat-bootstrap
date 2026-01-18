#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/ha-sat-bootstrap}"
UNIT_SRC="$REPO_DIR/systemd"

install -m 0644 "$UNIT_SRC/ha-sat-update@.service" /etc/systemd/system/ha-sat-update@.service

systemctl daemon-reload
