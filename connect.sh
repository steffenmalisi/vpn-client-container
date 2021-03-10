#!/usr/bin/env bash

. config/.net.cfg

CONTAINER_NAME=${1:-vpn}
CONTAINER_INFO=$(multipass info $CONTAINER_NAME 2>/dev/null || echo "State: NA")
CONTAINER_STATE=$(echo "$CONTAINER_INFO" | grep State | awk '{print $2}')

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

function add_routes(){
  echo
  echo "Adding routes on your host targeting $CONTAINER_IP"
  echo "This will need your host sudo password"
  echo
  for netmask in ${VPN_NETMASKS[@]}
  do
    sudo route -nq add -net $netmask $CONTAINER_IP
  done
  echo "...done"
}

function remove_routes(){
  echo
  echo "Removing routes configured in .net.cfg"
  echo "This will need your host sudo password"
  echo
  for netmask in ${VPN_NETMASKS[@]}
  do
    sudo route -nq delete -net $netmask $CONTAINER_IP
  done
  echo "...done"
}

function shutdown() {
  remove_routes
  multipass stop $CONTAINER_NAME
}

function configure_host(){
  echo
  echo "########################################"
  echo "           Configure host"
  echo "########################################"
  echo
  add_routes
}

function connect() {
  configure_host
  echo
  echo
  echo
  echo "########################################"
  echo "           Enter container"
  echo "########################################"
  echo
  multipass exec $CONTAINER_NAME openforti
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