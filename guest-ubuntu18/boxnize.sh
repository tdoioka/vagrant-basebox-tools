#!/bin/bash

#
# Install and setup for the requirements of the base box.
# After that clean up virtual hdd for compaction.
#
# *** NEVER RUN ON THE HOST OS. THIS CREATES A SECURITY HOLE. ***
#

set -ueo pipefail

# For install public base-box requirements.
# ................................................................

# For avoid update-initramfs error
echo "RESUME=UUID=$(lsblk -o fstype,uuid | grep swap | awk '{print $2}')" |
  sudo tee /etc/initramfs-tools/conf.d/resume
sudo update-initramfs -u

# Update/Upgrade packages not interactive.
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y \
  -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  -q full-upgrade

# Install and setup SSHD.
sudo apt install -y --no-install-recommends openssh-server
echo "UseDNS no" | sudo tee -a /etc/ssh/sshd_config
mkdir -p /home/vagrant/.ssh
wget --no-check-certificate -O /home/vagrant/.ssh/authorized_keys \
  'https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant.pub'
chown -R vagrant /home/vagrant/.ssh
chmod -R go-rwsx /home/vagrant/.ssh

# Setup sudoers.
sudo grep -E '^Defaults\s+env_keep="SSH_AUTH_SOCK"' /etc/sudoers >&/dev/null ||
  sudo sed -i -e '/Defaults\s\+env_reset/a Defaults\tenv_keep="SSH_AUTH_SOCK"' /etc/sudoers
sudo grep -E '^Defaults:vagrant\s+!requiretty' /etc/sudoers >&/dev/null ||
  sudo sed -i -e '/Defaults\s\+env_reset/a Defaults:vagrant\t!requiretty' /etc/sudoers
sudo grep -E '^Defaults\sexempt_group=sudo' /etc/sudoers >&/dev/null ||
  sudo sed -i -e '/Defaults\s\+env_reset/a Defaults\texempt_group=sudo' /etc/sudoers
sudo grep -E '^%vagrant\s+ALL=(ALL) NOPASSWD' /etc/sudoers >&/dev/null ||
  sudo sed -i -e '/%sudo\s\ALL=(ALL:ALL) ALL/a %vagrant\tALL=(ALL) NOPASSWD: ALL' /etc/sudoers

# Install Guest Addition.
sudo apt-get install -y --no-install-recommends \
  "linux-headers-$(uname -r)" build-essential dkms
sudo sh /media/vagrant/VBox_GAs_*/VBoxLinuxAdditions.run || test $? -eq 2

# For image shrink.
# ................................................................

# Remove no need package informations
sudo apt autoremove --purge -y
sudo apt autoclean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get clean

# Cleanup /var/log
sudo find /var/log/ -type f -exec cp -f /dev/null {} \;

# Deflag.
e4defrag /

# Fill 0 to empty space for shrink the virtual HDD.
echo "INFO: Fill 0 to empty space..." >&2
dd if=/dev/zero of=/var/tmp/ZERO bs=1M || true; rm /var/tmp/ZERO

# Remove command history.
cp -f /dev/null /home/vagrant/.bash_history
history -c
