#!/usr/bin/env bash

. config/.net.cfg

USAGE="
Usage: $0 [options] [container_name]

Options:
-a      Add hosts from config/.hosts.cfg to your /etc/hosts/file
        This can be used as an alternative to changing host's DNS configuration
-d      Disable changing host's DNS configuration
        Your host will not be able to resolve DNS names from your VPN
        See also option -a
-h      Display this help
-i      Specify the interface of your host which will be used for DNS settings
        On your Mac you can find the correct name using 'networksetup -listallnetworkservices'
-s      Shutdown container after VPN connection is shut down
        The default is that the container itself keeps running
        to have a faster startup for the next connect command
"

ADD_HOSTS=false
SHUTDOWN_CONTAINER=false
DISABLE_HOST_DNS=false
while getopts ':adhi:s' option; do
  case "$option" in
    a) ADD_HOSTS=true ;;
    d) DISABLE_HOST_DNS=true ;;
    h)
      echo "$USAGE"
      exit
      ;;
    i) HOST_INTERFACE=$OPTARG ;;
    s) SHUTDOWN_CONTAINER=true ;;
    :)
      printf "missing argument for -%s\\n" "$OPTARG" >&2
      echo "$USAGE" >&2
      exit 1
      ;;
    \\?)
      printf "illegal option: -%s\\n" "$OPTARG" >&2
      echo "$USAGE" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

if [[ "$(whoami)" != "root" ]]; then
	echo "This script requires to be run as root"
	echo "It modifies the routing table of your host and changes your DNS nameserver entry"
	echo "Please use sudo connect.sh"
	exit 1
fi

CONTAINER_NAME=${1:-vpn}
CONTAINER_INFO=$(multipass info $CONTAINER_NAME 2>/dev/null || echo "State: NA")
CONTAINER_STATE=$(echo "$CONTAINER_INFO" | grep State | awk '{print $2}')
# get real resolv.conf file of host
REALRESOLVCONF=$(greadlink -f /etc/resolv.conf)
# get real /etc/hosts file of host
REALETCHOSTS=$(greadlink -f /etc/hosts)
# get primary DNS server of host
HOST_DNS1=$(grep -E '^nameserver ' /etc/resolv.conf | head -1 | awk '{print $2}')

function check_macos_interface(){
  if [ "$DISABLE_HOST_DNS" = "false" ]; then
    if [ -z ${HOST_INTERFACE+x} ]; then
      echo "Get host interface for DNS settings"
      HOST_INTERFACE=$(networksetup -listnetworkserviceorder | grep $(route get example.com | grep interface | awk '{print $2}') | gsed -r 's/\(Hardware Port: (.*), .*/\1/g')
      echo "Using $HOST_INTERFACE"
      echo "...done"
      if [ -z ${HOST_INTERFACE+x} ]; then
        echo "The interface of your host which will be used for DNS settings could not be determined automatically."
        echo "Please use option -i of this script"
        exit 1
      fi
    fi
    # check if the interface is valid
    networksetup -getinfo "$HOST_INTERFACE" > /dev/null 2>&1 || INVALID_INTERFACE=true
    if [ "$INVALID_INTERFACE" = "true" ]; then
      echo "The interface '$HOST_INTERFACE' is not valid. Exiting."
      exit 1
    fi
  fi
}

check_macos_interface

case $CONTAINER_STATE in
  NA)
    echo "The container $CONTAINER_NAME is not available on your system."
    echo "Did you successfully run the installer script?"
    exit 1
    ;;
	Stopped)
    echo "Starting multipass container"
    multipass start $CONTAINER_NAME
    echo "...done"
		;;
	*)
		;;
esac

CONTAINER_IP=$(multipass info $CONTAINER_NAME | grep IPv4 | awk '{print $2}')


# ********************************* HOST CONFIGURATION **************************************

function add_host_routes(){
  echo
  echo "Adding routes on your host targeting $CONTAINER_IP"
  echo
  for netmask in ${VPN_NETMASKS[@]}
  do
    route -nq add -net $netmask $CONTAINER_IP
  done
  echo "...done"
}

function remove_host_routes(){
  echo
  echo "Removing routes configured in .net.cfg"
  echo
  for netmask in ${VPN_NETMASKS[@]}
  do
    route -nq delete -net $netmask $CONTAINER_IP
  done
  echo "...done"
}

function add_macos_host_dns(){
  if [ "$DISABLE_HOST_DNS" = "true" ]; then
    return 0
  fi

  echo
  echo "Setting the container IP $CONTAINER_IP as the primary DNS server for the host"
  echo
  # backing up the current setting
  networksetup -getdnsservers Wi-Fi | gsed -r "s/There aren't any DNS Servers set.*/empty/g" > macos_dns.conf.bak
  # setting the nameserver
  networksetup -setdnsservers "$HOST_INTERFACE" $CONTAINER_IP
  echo "...done"
}

function remove_macos_host_dns(){
  if [ "$DISABLE_HOST_DNS" = "true" ]; then
    return 0
  fi

  echo
  echo "Rolling back the host DNS configuration to previous state"
  echo
  networksetup -setdnsservers "$HOST_INTERFACE" $(cat macos_dns.conf.bak) && rm macos_dns.conf.bak
  echo "...done"
}

function add_host_dns(){
  if [ "$DISABLE_HOST_DNS" = "true" ]; then
    return 0
  fi

  echo
  echo "Setting the container IP $CONTAINER_IP as the primary DNS server for the host"
  echo
  # merge the new nameservers with the other options from the old configuration
  {
    echo "nameserver $CONTAINER_IP"
    grep --invert-match '^nameserver[[:space:]]' "$REALRESOLVCONF" || true
  } > "$REALRESOLVCONF.tmp"

  # backup the old configuration and install the new one
  cp -a "$REALRESOLVCONF" "$REALRESOLVCONF.bak"
  mv -f "$REALRESOLVCONF.tmp" "$REALRESOLVCONF"

  echo "...done"
}

function remove_host_dns(){
  if [ "$DISABLE_HOST_DNS" = "true" ]; then
    return 0
  fi

  echo
  echo "Rolling back the host DNS configuration to previous state"
  echo
  mv -f "$REALRESOLVCONF.bak" "$REALRESOLVCONF"
  echo "...done"
}

function add_hosts() {
  if [ "$ADD_HOSTS" = "false" ]; then
    return 0
  fi

  echo
  echo "Modifying your /etc/hosts. A backup will be created."
  echo

  # backup the old hosts file
  sudo cp -a "$REALETCHOSTS" "$REALETCHOSTS.bak"

  for host in ${HOSTS[@]}
  do
    echo "Check for host $host"
    if ! grep -q "$host" $REALETCHOSTS; then
      ipv4=$(multipass exec $CONTAINER_NAME dig +noall +answer +yaml $host | grep -E ' A ' | awk '{print $6}')
      if [ -n "$ipv4" ]; then
        echo "Adding $ipv4 $host"
        echo "$ipv4 $host" | sudo tee -a "$REALETCHOSTS"
      else
        echo "No IPv4 for host $host could be found. Skipping..."
      fi
    fi
    echo "...done"
    echo
  done
}

function remove_hosts() {
  if [ "$ADD_HOSTS" = "false" ]; then
    return 0
  fi

  echo
  echo "Rolling back /etc/hosts configuration to previous state"
  echo
  mv -f "$REALETCHOSTS.bak" "$REALETCHOSTS"
  echo "...done"
}

# ****************************** CONTAINER CONFIGURATION ************************************

function add_container_routes(){
  echo
  echo "Adding route within the container to still resolve the hosts privary DNS $HOST_DNS1 even after connection to VPN"
  echo
  multipass exec $CONTAINER_NAME -- sudo route -n add -host $HOST_DNS1 gw 192.168.64.1
  echo "...done"
}

function remove_container_routes(){
  echo
  echo "Removing previously set routes within the container"
  echo
  multipass exec $CONTAINER_NAME -- sudo route -n delete -host $HOST_DNS1 gw 192.168.64.1
  echo "...done"
}

function add_container_dns(){
  if [ "$DISABLE_HOST_DNS" = "true" ]; then
    return 0
  fi
  echo
  echo "Setting the host DNS $HOST_DNS1 as the primary DNS server for the container"
  echo
  multipass exec $CONTAINER_NAME -- sudo mv -f /etc/dnsmasq.d/server.conf /etc/dnsmasq.d/server.conf.bak
  multipass exec $CONTAINER_NAME -- bash -c "echo 'server=$HOST_DNS1' | sudo tee /etc/dnsmasq.d/server.conf"
  multipass exec $CONTAINER_NAME -- sudo systemctl restart dnsmasq
  echo "...Done"
}

function remove_container_dns(){
  if [ "$DISABLE_HOST_DNS" = "true" ]; then
    return 0
  fi
  echo
  echo "Rolling back the container DNS configuration to previous state"
  echo
  multipass exec $CONTAINER_NAME -- sudo mv -f /etc/dnsmasq.d/server.conf.bak /etc/dnsmasq.d/server.conf
  multipass exec $CONTAINER_NAME -- sudo systemctl restart dnsmasq
  echo "...Done"
}

# ************************************** CONNECT ********************************************

function connect() {
  echo
  echo
  echo
  echo "########################################"
  echo "           Let's connect"
  echo "########################################"
  echo
  multipass exec $CONTAINER_NAME openforti connect
  add_host_routes
  add_macos_host_dns
  add_hosts
  add_container_routes
  add_container_dns
  multipass exec $CONTAINER_NAME openforti logs
}

function shutdown() {
  remove_host_routes
  remove_macos_host_dns
  remove_hosts
  remove_container_routes
  remove_container_dns
  if [ "$SHUTDOWN_CONTAINER" = "true" ]; then
    multipass stop $CONTAINER_NAME
  fi
}

trap "echo 'Terminated!' && exit;" SIGINT SIGTERM

# connect keeps running until quit by the user
# so we will excecute shutdown directly when done
connect && shutdown

echo
echo
echo "########################################"
echo "               Goodbye"
echo "########################################"
echo