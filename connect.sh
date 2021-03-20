#!/usr/bin/env bash

. config/.net.cfg

USAGE="
Usage: $0 [options] [container_name]

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
"

# ************************************* GET OPTIONS *****************************************

CONNECT_SYNC_FILE=".connect"
MACOS_DNS_BACKUP_FILE="macos_dns.conf.bak"
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

# ************************************* PRE CHECKS ******************************************

function check_prerequisites() {
  # script was run as root
  if [[ "$(whoami)" != "root" ]]; then
    echo "This script requires to be run as root"
    echo "It modifies the routing table of your host and changes your DNS nameserver entry"
    echo "Please use sudo connect.sh"
    exit 1
  fi

  # multipass has to be installed
  if ! type "multipass" >/dev/null 2>&1; then
    echo "Multipass is not available on your system."
    if [[ "$OSTYPE" =~ ^darwin ]]; then
      echo "You can install it using 'brew install multipass'"
    fi
    exit 1;
  fi

  # gsed has to be installed
  if ! type "gsed" >/dev/null 2>&1; then
    echo "gsed is not available on your system."
    if [[ "$OSTYPE" =~ ^darwin ]]; then
      echo "You can install it using 'brew install gsed'"
    fi
    exit 1;
  fi

  # greadlink has to be installed
  if ! type "greadlink" >/dev/null 2>&1; then
    echo "greadlink is not available on your system."
    if [[ "$OSTYPE" =~ ^darwin ]]; then
      echo "You can install it using 'brew install coreutils'"
    fi
    exit 1;
  fi

  # VPN_NETMASKS variable has to be present
  if [ -z "$VPN_NETMASKS" ]; then
    echo "Please configure VPN_NETMASKS in ./config/.net.cfg"
    exit 1;
  fi

  # VPN_DOMAINS variable has to be present when DISABLE_HOST_DNS is false
  if [ "$DISABLE_HOST_DNS" = "false" ]; then
    if [ -z "$VPN_DOMAINS" ]; then
      echo "Please configure VPN_DOMAINS in ./config/.net.cfg"
      exit 1;
    fi
  fi

  # VPN_HOSTS has to be present when ADD_HOSTS is true
  if [ "$ADD_HOSTS" = "true" ]; then
    if [ -z "$VPN_HOSTS" ]; then
      echo "Please configure VPN_HOSTS in ./config/.net.cfg"
      exit 1;
    fi
  fi
}

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

function pre_check(){
  check_prerequisites
  check_macos_interface
}

pre_check

CONTAINER_NAME=${1:-vpn}
CONTAINER_INFO=$(multipass info $CONTAINER_NAME 2>/dev/null || echo "State: NA")
CONTAINER_STATE=$(echo "$CONTAINER_INFO" | grep State | awk '{print $2}')
CONTAINER_IP=$(multipass info $CONTAINER_NAME | grep IPv4 | awk '{print $2}')
# get real resolv.conf file of host
REALRESOLVCONF=$(greadlink -f /etc/resolv.conf)
# get real /etc/hosts file of host
REALETCHOSTS=$(greadlink -f /etc/hosts)

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
  echo
  echo "Setting the container IP $CONTAINER_IP as the primary DNS server for the host"
  echo
  # backup the current setting
  echo "$HOST_INTERFACE" > $MACOS_DNS_BACKUP_FILE
  networksetup -getdnsservers Wi-Fi | gsed -r "s/There aren't any DNS Servers set.*/empty/g" >> $MACOS_DNS_BACKUP_FILE
  # set the nameserver
  networksetup -setdnsservers "$HOST_INTERFACE" $CONTAINER_IP
  # flush DNS
  dscacheutil -flushcache
  killall -HUP mDNSResponder
  echo "...done"
}

function remove_macos_host_dns(){
  echo
  echo "Rolling back the host DNS configuration to previous state"
  echo
  networksetup -setdnsservers $(cat $MACOS_DNS_BACKUP_FILE) && rm $MACOS_DNS_BACKUP_FILE
  # flush DNS
  dscacheutil -flushcache
  killall -HUP mDNSResponder
  echo "...done"
}

function add_host_dns(){
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
  echo
  echo "Rolling back the host DNS configuration to previous state"
  echo
  mv -f "$REALRESOLVCONF.bak" "$REALRESOLVCONF"
  echo "...done"
}

function add_hosts() {
  echo
  echo "Modifying your /etc/hosts. A backup will be created."
  echo

  # backup the old hosts file
  sudo cp -a "$REALETCHOSTS" "$REALETCHOSTS.bak"

  for host in ${VPN_HOSTS[@]}
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
  echo
  echo "Setting the host DNS $HOST_DNS1 as the primary DNS server for the container"
  echo
  multipass exec $CONTAINER_NAME -- sudo mv -f /etc/dnsmasq.d/server.conf /etc/dnsmasq.d/server.conf.bak
  multipass exec $CONTAINER_NAME -- bash -c "echo 'server=$HOST_DNS1' | sudo tee /etc/dnsmasq.d/server.conf"
  multipass exec $CONTAINER_NAME -- sudo systemctl restart dnsmasq
  echo "...Done"
}

function remove_container_dns(){
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
  touch $CONNECT_SYNC_FILE
  multipass exec $CONTAINER_NAME openforti connect
  add_host_routes
  if [ "$ADD_HOSTS" = "true" ]; then
    add_hosts
  fi
  if [ "$DISABLE_HOST_DNS" = "false" ]; then
    add_macos_host_dns
    add_container_routes
    add_container_dns
  fi

  multipass exec $CONTAINER_NAME openforti logs
}

function shutdown() {
  remove_host_routes
  if [ "$ADD_HOSTS" = "true" ]; then
    remove_hosts
  fi
  if [ "$DISABLE_HOST_DNS" = "false" ]; then
    remove_macos_host_dns
    remove_container_routes
    remove_container_dns
  fi
  if [ "$SHUTDOWN_CONTAINER" = "true" ]; then
    multipass stop $CONTAINER_NAME
  fi

  rm -f $CONNECT_SYNC_FILE
}

function kill_other_instance_if_running(){
  pid=$(ps -fe | grep '[b]ash ./connect.sh' | grep -v $$ | awk '{print $2}')
  if [[ -n $pid ]]; then
    echo "Another instance of this script is running. Will kill it's process"
    child_pid=$(ps -e -o pid,ppid | awk '$2~/'$pid'/ {print $1}')
    echo "Kill child process $child_pid"
    kill -2 $child_pid
    while ps -p "$pid"; do
      echo "Waiting for process $pid to shutdown..."
      sleep 5
    done
  fi
}

function check_previous_graceful_shutdown(){
  if test -f $CONNECT_SYNC_FILE; then
    echo "Seems like you did not gracefully shutdown this script. This can leave your DNS settings and therefore your internet connection broken"
    echo "Please always exit the script with CTRL-C to that it can cleanup its resources"
    kill_other_instance_if_running
    remove_host_routes
    if test -f $MACOS_DNS_BACKUP_FILE; then
      remove_macos_host_dns
      remove_container_routes
      remove_container_dns
    fi
    if test -f "$REALRESOLVCONF.bak"; then
      remove_host_dns
      remove_container_routes
      remove_container_dns
    fi
    if test -f "$REALETCHOSTS.bak"; then
      remove_hosts
    fi
  fi
}

trap "echo 'Terminated!' && exit;" SIGINT SIGTERM

check_previous_graceful_shutdown

# get primary DNS server of host
HOST_DNS1=$(grep -E '^nameserver ' /etc/resolv.conf | head -1 | awk '{print $2}')

# connect keeps running until quit by the user
# so we will excecute shutdown directly when done
connect
shutdown

echo
echo
echo "########################################"
echo "               Goodbye"
echo "########################################"
echo