#!/usr/bin/env bash

set -eu

# Initializing DNS from cloud-init is currently not working.
# After switching from systemd-resolved to DNSMasq from within the cloud-init process
# the container looses network connectivity to the host and stays in an undefined state.

# This script serves as a workaround.

echo "Switch from systemd-resolved to DNSMasq"
sudo rm /etc/resolv.conf
echo 'nameserver 127.0.0.1' | sudo tee /etc/resolv.conf >/dev/null 2>&1
sudo resolvectl flush-caches
sudo systemctl disable systemd-resolved.service >/dev/null 2>&1
sudo systemctl stop systemd-resolved >/dev/null 2>&1
sudo systemctl restart dnsmasq

echo "********************************************"
echo "** VPN container successfully initialized **"
echo "********************************************"