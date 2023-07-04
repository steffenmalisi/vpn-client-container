# VPN Client Container

Route your VPN traffic from your host through a container using Split Tunneling.


# DISCLAIMER

Even having many advantages, Split Tunneling can be a security risk if your infrastructure connected to the VPN is not protected accordingly.

Therefore it may be forbidden by security guidelines. If you are using your company network, it may be prohibited by company managed rules on your client to change routing configuration and as a consequence this tool doesn't even work.

Please make sure that you fully understand the advantages and drawbacks of Split Tunneling before using this tool:
* https://en.wikipedia.org/wiki/Split_tunneling
* https://www.infosecurity-magazine.com/opinions/vpn-split-tunneling/


# Prerequisites

## Install Multipass
[Multipass](https://multipass.run/) orchestrates virtual Ubuntu instances.

These scripts use multipass to deploy a container that connects to your VPN. Docker was not an option because Docker Desktop for Mac does not have the necessary modules compiled into the kernel, which are needed for a PPPoE connection.

You need to have `multipass` installed on the command line.

For Mac you can install it with `brew install multipass`

## (On a Mac) Install coreutils

The connect script needs `gsed`, `greadlink` and `gdate` to be available as binaries from your Terminal.

You can install them with
```bash
brew install gsed
brew install coreutils
```

# Install

## 1. Provide your VPN configuration

You need to provide two files within the `config` folder

### 1.1 .net.cfg
Place a file named `.net.cfg` into the `config` folder. You have the following configuration options of your network:
```bash
# VPN_NETMASKS (mandatory) contains the CIDRs of your VPN.
# It is used to route traffic for these CIDRs through the container
VPN_NETMASKS=(
  10.0.0.0/16
  10.1.0.0/16
)

# VPN_DOMAINS (mandatory, but optional if using the -d option of the connect script).
# This variable is used to route DNS queries for these domains to your VPN
VPN_DOMAINS=(
  vpn-domain.de
  internal.company.com
)

# VPN_HOSTS (optional, but mandatory if using the -a option of the connect script).
# You can put any single host here, that is not covered by VPN_NETMASKS.
# The script will resolve the IP Adresses and route them trough your VPN.
# Additionally, if you use the -a option these hosts are written to your /etc/hosts file.
VPN_HOSTS=(
  any-host.of.mycompany.com
  vpnhost.vpn-domain.de
)
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
TWO_F_TIMEOUT=15
```

## 2. Run the installer script

To initialize and launch a container, run:

```bash
git clone https://github.com/steffenmalisi/vpn-client-container.git
cd vpn-client-container
./install.sh
```

The script does:
- launch a multipass container with a cloud config provided in `container-config.yml`
- mount the `scripts` and `config` folder into the launched container

If you previously ran this script, it is a good idea to clean up first:
```bash
multipass delete vpn
multipass purge
```

# Connect to your VPN

To connect to your VPN, run:

```bash
./connect.sh
```

Available options:
```
./connect.sh -h

Usage: ./connect.sh [options] [container_name]

Options:
-a      Add hosts from config/.net.cfg to your /etc/hosts/file
        This can be used as an alternative to changing host's DNS configuration
-d      Disable changing host's DNS configuration
        Your host will not be able to resolve DNS names from your VPN
        See also option -a
-h      Display this help
-i      Specify the interface of your host which will be used for DNS settings
        On your Mac you can find the correct name using 'networksetup -listallnetworkservices'
        By default this script finds out the correct interface automatically
        To override this behaviour use this option
-s      Shutdown container after VPN connection is shut down
        The default is that the container itself keeps running
        to have a faster startup for the next connect command
```

The script does:
- Runs the openforti command within the container to connect to your VPN
- Modify your routing table on the host so that traffic for your VPN is routed through the container
- Modify your host's primary DNS server to point to the VPN container (can be disabled with -d)
- Optionally add hosts to your host's /etc/hosts :-). Can be activated with the -a option. Host hosts host
- Add a route to the container so that the local container network still is able to connect to your host
- Adds your initial host primary DNS as primary DNS for the container (can be disabled with -d)
- Keeps the connection open until interrupted with CTRL+C
- When interrupted it closes the connection and reverts all of the config changes made
- Optionally stops the container when option -s is given

# Uninstall
To uninstall the container just run
```bash
multipass delete vpn && multipass purge
```

# Q&A

## Q: I do not want my /etc/hosts or Host DNS to be changed by the script
A: Run it with ./connect -d and manually place your hosts into `/etc/hosts`. To get the IP Address for a host you can run `multipass exec vpn nslookup <hostname>`

## Q: What if the script is not able to clean up as expected
A: For all the changes on the host backup files are created. If anything goes wrong you can manually revert the changes.

Backup-Files:
- ./macos_dns.conf.bak: Contains initial host DNS information for the selected interface. You can manually restore by running `networksetup -setdnsservers "$HOST_INTERFACE" $(cat macos_dns.conf.bak)`
- /etc/hosts.bak: This is a copy of the initial /etc/hosts file. Revert to it with `mv -f "/etc/hosts.bak" "/etc/hosts"`

For problems with the container, just delete and reinstall it. See Install procedure.

# Known issues (PRs welcome)

## Support for multiple Host OSs
Currently the scripts are only tested on MacOS, but should also run on any other UNIX based OS.

## Support for multiple VPN solutions
These scripts currently only support Fortinet VPN via [openfortivpn](https://github.com/adrienverge/openfortivpn).