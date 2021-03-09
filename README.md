# VPN Client Container

Route your VPN traffic from your host through a container.

# Prerequisites

## Install Multipass
[Multipass](https://multipass.run/) orchestrates virtual Ubuntu instances.

These scripts use multipass to deploy a container that connects to your VPN. Docker was not an option because Docker Desktop for Mac does not have the necessary modules compiled into the kernel, which are needed for a PPPoE connection.

You need to have `multipass` installed on the command line.

For Mac you can install it with `brew install multipass`

# Installation

## 1. Provide your VPN configuration

You need to provide two files within the `config` folder

### 1.1 .net.cfg
Place a file named `.net.cfg` into the `config` folder. This file contains the CIDRs of your VPN. It is used to route traffic for these CIDRs through the container.
```bash
VPN_NETMASKS=(10.0.0.0/16 10.1.0.0/16)
```

### 1.2 .openforti.cfg
Place a file named `.openforti.cfg` into the `config` folder. This file contains your VPN configuration.
```bash
CONNECTION_NAME="myvpn"
USERNAME="steffenmalisi"
PASSWORD="viastdin" # viastdin makes you enter it each time!
VPN_GW="my-vpn-gateway-host:443"
GWCERT_HASH="public key hash"
CONNECT_CONFIG="any pppd config"
LOG_FILE=$HOME/openforti.log
```

## 2. Run the installer script

To initialize and launch a container, run:

```bash
git clone https://github.com/steffenmalisi/vpn-client-container.git
cd vpn-client-container
./install.sh
```
The script does:
- launch a multipass container with a cloud config provided by `container-config.yml`
- mount the `scripts` and `config` folder into the launched container

# Connect to your VPN

To connect to your VPN, run:

```bash
./connect.sh
```

The script does:
- Modify your routing table on the host so that traffic for your VPN is routed through the container
- Runs the openforti command within the container to connect to your VPN
- Keeps the connection open until interrupted with CTRL+C
- When interrupted it closes the connection, reverts your host config and stops the container

# Known issues (PRs welcome)

## DNS resolution on the host
Currently DNS resolution is not supported. To be able to resolve DNS names from your host, you have to edit your `/etc/hosts`
To get the IP Address for a host to add it to `/etc/hosts` you can run `multipass exec vpn nslookup <hostname>`

## Support for multiple Host OSs
Currently the scripts are only tested on MacOS, but should also run on any other UNIX based OS.

## Support for multiple VPN solutions
These scripts currently only support Fortinet VPN via [openfortivpn](https://github.com/adrienverge/openfortivpn).