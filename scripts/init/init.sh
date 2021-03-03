#!/usr/bin/env bash

echo "*******************************************************************************************"
echo "Initialising container"
echo "In a future release this can be done directly with cloud-init."
echo "But currently https://github.com/canonical/multipass/issues/1039 is blocking from doing so"
echo "*******************************************************************************************"

echo "***** Update package sources"
sudo apt-get update -qy
echo "***** Done"
echo ""
echo "***** Upgrade packages"
sudo apt-get upgrade -qy
echo "***** Done"
echo ""
echo "***** Install new packages"
sudo apt-get install -qy net-tools openconnect openfortivpn
echo "***** Done"
echo ""
echo "***** Link binaries"
sudo ln -s /opt/openfortivpn/openforti.sh /usr/local/bin/openforti
sudo ln -s /opt/nat/nat-init.sh /usr/local/bin/nat-init
echo "***** Done"

echo ""
echo "VPN container successfully initialized"