#!/usr/bin/env bash
set -euo pipefail

# Copy firstboot unit into systemd and enable it, then disable this enroll unit.
cp /boot/ha-satellite-firstboot.service /etc/systemd/system/ha-satellite-firstboot.service
chmod 0644 /etc/systemd/system/ha-satellite-firstboot.service

systemctl daemon-reload
systemctl enable ha-satellite-firstboot.service

# disable self (this enroll unit)
systemctl disable firstboot-enroll.service || true
rm -f /etc/systemd/system/firstboot-enroll.service || true
systemctl daemon-reload || true
