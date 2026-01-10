# Stop runtime services
sudo systemctl stop ssh
sudo systemctl stop ha-satellite.service
sudo systemctl stop ha-satellite-firstboot 
sudo systemctl stop ha-satellite-mq-agent

# Reset identity
sudo rm -f /etc/ssh/ssh_host_*
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id
sudo rm -f /etc/ha-satellite/.provisioned
sudo rm -f /etc/ha-satellite/satellite.env
sudo rm -f /etc/ha-satellite/mq_agent.env

# Re-assert boot policy
sudo systemctl enable ssh
sudo systemctl enable ssh-hostkey-bootstrap.service
sudo systemctl enable NetworkManager

# Optional hygiene
rm -f ~/.bash_history
sudo rm -f /root/.bash_history

# Flush filesystem buffers
sync

echo
echo "============================================================"
echo " Golden Image Prep Complete"
echo "============================================================"
echo
echo "System identity has been reset and services stopped."
echo
echo "Next steps:"
echo
echo "  • Reboot  : Re-run firstboot and re-apply configuration"
echo "              (use this to validate before capture)"
echo
echo "  • Shutdown: Power off now to safely capture the SD card"
echo "              (do NOT reboot before imaging)"
echo
echo "Choose ONE:"
echo
echo "  sudo reboot"
echo "  sudo poweroff"
echo
echo "============================================================"

