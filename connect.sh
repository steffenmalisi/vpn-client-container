#!/usr/bin/env bash

cd "$(dirname "$0")"

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
CONNECT_LOG_FILE="log/connect.log"
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

COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_DEFAULT="\e[39m"
RESET_CONSOLE_LINE="\r\033[K"

function log() {
  echo "[$$] $(date) $1 $2" >> $CONNECT_LOG_FILE
}

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
      log "DEBUG" "Get host interface for DNS settings"
      HOST_INTERFACE=$(networksetup -listnetworkserviceorder | grep $(route get example.com | grep interface | awk '{print $2}') | gsed -r 's/\(Hardware Port: (.*), .*/\1/g')
      log "INFO" "Using $HOST_INTERFACE as host interface for DNS settings"
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
  log "DEBUG" "***************************************************************"
  check_macos_interface
}

pre_check

CONTAINER_NAME=${1:-vpn}
CONTAINER_INFO=$(multipass info $CONTAINER_NAME 2>/dev/null || echo "State: NA")
CONTAINER_STATE=$(echo "$CONTAINER_INFO" | grep State | awk '{print $2}')
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
    log "DEBUG" "Starting multipass container"
    multipass start $CONTAINER_NAME
    log "DEBUG" "Multipass container started"
    ;;
  *)
    ;;
esac

CONTAINER_IP=$(multipass info $CONTAINER_NAME | grep IPv4 | awk '{print $2}')

# ********************************* HOST CONFIGURATION **************************************

function add_host_routes(){
  log "DEBUG" "Adding routes on your host targeting $CONTAINER_IP"
  for netmask in ${VPN_NETMASKS[@]}
  do
    route -nq add -net $netmask $CONTAINER_IP >> $CONNECT_LOG_FILE 2>&1
    log "DEBUG" "Route $netmask $CONTAINER_IP added"
  done
}

function remove_host_routes(){
  log "DEBUG" "Delete routes configured in .net.cfg"
  for netmask in ${VPN_NETMASKS[@]}
  do
    route -nq delete -net $netmask $CONTAINER_IP >> $CONNECT_LOG_FILE 2>&1
    log "DEBUG" "Route $netmask $CONTAINER_IP deleted"
  done
}

function add_macos_host_dns(){
  # backup the current setting
  host_dns_servers=$(networksetup -getdnsservers Wi-Fi | gsed -r "s/There aren't any DNS Servers set.*/empty/g")
  echo "$HOST_INTERFACE" > $MACOS_DNS_BACKUP_FILE
  echo "$host_dns_servers" >> $MACOS_DNS_BACKUP_FILE
  log "DEBUG" "Backed up host DNS servers for interface '$HOST_INTERFACE': $host_dns_servers"
  # set the nameserver
  networksetup -setdnsservers "$HOST_INTERFACE" $CONTAINER_IP
  log "DEBUG" "Set the container IP $CONTAINER_IP as the primary DNS server for the host"
  # flush DNS
  dscacheutil -flushcache
  killall -HUP mDNSResponder
  log "DEBUG" "Host DNS cache flushed"
}

function remove_macos_host_dns(){
  if ! test -f $MACOS_DNS_BACKUP_FILE; then
    log "DEBUG" "No backup file of MacOS host DNS exists"
    return 0
  fi
  log "DEBUG" "Rolling back the host DNS configuration to previous state"
  networksetup -setdnsservers $(cat $MACOS_DNS_BACKUP_FILE) && rm $MACOS_DNS_BACKUP_FILE
  # flush DNS
  dscacheutil -flushcache
  killall -HUP mDNSResponder
  log "DEBUG" "Host DNS cache flushed"
}

function add_host_dns(){
  # backup the current setting
  cp -a "$REALRESOLVCONF" "$REALRESOLVCONF.bak"
  log "DEBUG" "Backed up host DNS servers to $REALRESOLVCONF.bak"
  # merge the new nameservers with the other options from the old configuration
  {
    echo "nameserver $CONTAINER_IP"
    grep --invert-match '^nameserver[[:space:]]' "$REALRESOLVCONF" || true
  } > "$REALRESOLVCONF.tmp"
  log "DEBUG" "Set the container IP $CONTAINER_IP as the primary DNS server for the host"
  # install the new setting
  mv -f "$REALRESOLVCONF.tmp" "$REALRESOLVCONF"
}

function remove_host_dns(){
  if ! test -f "$REALRESOLVCONF.bak"; then
    log "DEBUG" "No backup file of host DNS exists"
    return 0
  fi
  mv -f "$REALRESOLVCONF.bak" "$REALRESOLVCONF"
  log "DEBUG" "Rolled back the host DNS configuration to previous state"
}

function add_hosts() {
  log "DEBUG" "Modifying your /etc/hosts. A backup will be created."
  # backup the old hosts file
  sudo cp -a "$REALETCHOSTS" "$REALETCHOSTS.bak"
  log "DEBUG" "Backed up hosts file to $REALETCHOSTS.bak"
  for host in ${VPN_HOSTS[@]}; do
    log "DEBUG" "Check for host $host"
    if ! grep -q "$host" $REALETCHOSTS; then
      ipv4=$(multipass exec $CONTAINER_NAME dig +noall +answer +yaml $host | grep -E ' A ' | awk '{print $6}')
      if [ -n "$ipv4" ]; then
        echo "$ipv4 $host" | sudo tee -a "$REALETCHOSTS"
        log "DEBUG" "Added $ipv4 $host"
      else
        log "DEBUG" "No IPv4 for host $host could be found. Skipping..."
      fi
    fi
  done
}

function remove_hosts() {
  if ! test -f $MACOS_DNS_BACKUP_FILE; then
    log "DEBUG" "No backup file of hosts /etc/hosts file exists"
    return 0
  fi
  mv -f "$REALETCHOSTS.bak" "$REALETCHOSTS"
  log "DEBUG" "Rolled back /etc/hosts configuration to previous state"
}

# ****************************** CONTAINER CONFIGURATION ************************************

function add_container_routes(){
  multipass exec $CONTAINER_NAME -- sudo route -n add -host $HOST_DNS1 gw 192.168.64.1 >> $CONNECT_LOG_FILE 2>&1
  log "DEBUG" "Added route within the container to still resolve the hosts privary DNS $HOST_DNS1 even after connection to VPN"
}

function remove_container_routes(){
  multipass exec $CONTAINER_NAME -- sudo route -n delete -host $HOST_DNS1 gw 192.168.64.1 >> $CONNECT_LOG_FILE 2>&1
  log "DEBUG" "Removed previously set routes within the container"
}

function add_container_dns(){
  log "DEBUG" "Setting the host DNS $HOST_DNS1 as the primary DNS server for the container"
  multipass exec $CONTAINER_NAME -- sudo mv -f /etc/dnsmasq.d/server.conf /etc/dnsmasq.d/server.conf.bak >> $CONNECT_LOG_FILE 2>&1
  multipass exec $CONTAINER_NAME -- bash -c "echo 'server=$HOST_DNS1' | sudo tee 1> /dev/null /etc/dnsmasq.d/server.conf" >> $CONNECT_LOG_FILE 2>&1
  multipass exec $CONTAINER_NAME -- sudo systemctl restart dnsmasq >> $CONNECT_LOG_FILE 2>&1
  log "DEBUG" "Done"
}

function remove_container_dns(){
  if ! multipass exec $CONTAINER_NAME -- bash -c "test -f /etc/dnsmasq.d/server.conf.bak"; then
    log "DEBUG" "No backup file /etc/dnsmasq.d/server.conf.bak in container exists"
    return 0
  fi
  log "DEBUG" "Rolling back the container DNS configuration to previous state"
  multipass exec $CONTAINER_NAME -- sudo mv -f /etc/dnsmasq.d/server.conf.bak /etc/dnsmasq.d/server.conf
  multipass exec $CONTAINER_NAME -- sudo systemctl restart dnsmasq
  log "DEBUG" "Done"
}

# ************************************** CONNECT ********************************************

function connect() {
  touch $CONNECT_SYNC_FILE
    while true
  do
    sleep 10
  done
}

function connect2() {
  echo -en "$RESET_CONSOLE_LINE"
  #rm -f $CONNECT_LOG_FILE
  log "DEBUG" "Let's connect..."
  touch $CONNECT_SYNC_FILE
  multipass exec $CONTAINER_NAME openforti connect
  for i in {1..10}; do
    if ! multipass exec $CONTAINER_NAME openforti status; then
      echo -en "$RESET_CONSOLE_LINE"
      echo -n "Waiting for connection $i"
      status="Connecting"
      sleep 2
    else
      status="Connected"
      break
    fi
  done
  echo -en "$RESET_CONSOLE_LINE"
  if [ "$status" != "Connected" ]; then
    echo
    echo "Could not connect to the VPN in a reasonable time."
    echo "Please try again."
    shutdown
    exit 1;
  else
    echo -en "$COLOR_GREEN$status$COLOR_DEFAULT"
  fi
  add_host_routes
  if [ "$ADD_HOSTS" = "true" ]; then
    add_hosts
  fi
  if [ "$DISABLE_HOST_DNS" = "false" ]; then
    add_macos_host_dns
    add_container_routes
    add_container_dns
  fi

  while true
  do
    sleep 10
  done
}

function shutdown() {
  echo -en "$RESET_CONSOLE_LINE"
  echo -en "Shutting down"
  remove_host_routes
  if [ "$ADD_HOSTS" = "true" ]; then
    remove_hosts
  fi
  if [ "$DISABLE_HOST_DNS" = "false" ]; then
    remove_macos_host_dns
    remove_container_routes
    remove_container_dns
  fi
  multipass exec $CONTAINER_NAME openforti stop
  if [ "$SHUTDOWN_CONTAINER" = "true" ]; then
    multipass stop $CONTAINER_NAME
  fi
  echo -en "$RESET_CONSOLE_LINE"
  echo -en "${COLOR_RED}Disconnected${COLOR_DEFAULT}"
  rm -f $CONNECT_SYNC_FILE
}

function kill_other_instance_if_running(){
  pid=$(ps -fe | grep '[b]ash .*connect.sh' | grep -v $$ | awk '{print $2}')
  if [[ -n $pid ]]; then
    echo "Another instance of this script is running. Will kill it's process"
    log "DEBUG" "Kill process $pid"
    kill -s INT $pid
    while ps -p "$pid" > /dev/null 2>&1; do
      echo "Waiting for process $pid to shutdown..."
      sleep 3
    done
  fi
}

function check_previous_graceful_shutdown(){
  if test -f $CONNECT_SYNC_FILE; then
    echo "*******************************************************************************"
    echo -en  "${COLOR_RED}"
    echo "Seems like you did not gracefully shutdown this script."
    echo "This can leave your DNS settings and therefore your internet connection broken"
    echo "Please always exit the script with CTRL-C to that it can cleanup its resources"
    echo -e "${COLOR_DEFAULT}"
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
    echo "*******************************************************************************"
  fi
}

trap "shutdown && exit;" SIGINT SIGTERM

check_previous_graceful_shutdown

# get primary DNS server of host
HOST_DNS1=$(grep -E '^nameserver ' /etc/resolv.conf | head -1 | awk '{print $2}')

# connect keeps running until quit by the user
connect