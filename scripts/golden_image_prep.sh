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
rm -f /home/scott/.bash_history
sudo rm -f /root/.bash_history

# Flush filesystem buffers
sync

# Power off for imaging (do NOT reboot)
# sudo poweroff

