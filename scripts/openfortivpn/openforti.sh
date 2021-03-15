#!/bin/bash

. $HOME/.config/.openforti.cfg

VERBOSE=false
while getopts ':v' option; do
  case "$option" in
    v) VERBOSE=true ;;
  esac
done

function write_connection_config() {
  sudo mkdir -p /etc/ppp/peers
  sudo bash -c "echo $CONNECT_CONFIG > /etc/ppp/peers/$CONNECTION_NAME"
}

function read_password() {
  case $PASSWORD in
    viastdin)
      read -s -p "Enter VPN password for ${USERNAME}: " PASSWORD
      ;;
    *)
      echo "You are storing your password in the config file. You should only do this for testing purposes"
      ;;
  esac
}

function establish_connection() {
  echo "Establishing openforti connection for ${USERNAME} to ${VPN_GW}"
  if [ "$VERBOSE" = "true" ]; then
    echo $PASSWORD | sudo openfortivpn "${VPN_GW}" -u "${USERNAME}" --trusted-cert "${GWCERT_HASH}" --no-dns --pppd-call="${CONNECTION_NAME}" --pppd-log "${LOG_FILE}" -vvv >> $LOG_FILE 2>&1 &
  else
    echo $PASSWORD | sudo openfortivpn "${VPN_GW}" -u "${USERNAME}" --trusted-cert "${GWCERT_HASH}" --no-dns --pppd-call="${CONNECTION_NAME}" >> $LOG_FILE 2>&1 &
  fi
}

function second_factor() {
  echo
  echo "You may now have to check your second authentication factor"
  echo
  sleep 15;
}

function configure_nat(){
  echo "Configuring NAT"
  . /opt/nat/nat-init.sh
  echo "...done"
}

function close_connection() {
  echo "Closing openforti connection"
  sudo pkill -SIGINT openfortivpn
  sleep 3;
  echo "...done"
}

function flush_dns () {
  echo "Flushing DNS"
  sudo systemctl restart dnsmasq
  echo "...done"
}

function connect(){
  echo "$(date)"
  shutdown
  echo
  echo "########################################"
  echo "    Establishing new VPN connection"
  echo "########################################"
  echo
  write_connection_config
  read_password
  establish_connection
  second_factor
  configure_nat
  echo
  echo
  echo
}

function shutdown() {
  echo
  echo
  echo "########################################"
  echo " Shutting down existing VPN connection"
  echo "########################################"
  echo
  close_connection
	flush_dns
}

trap "shutdown 2>&1 | tee -a $LOG_FILE && exit;" SIGINT SIGTERM

echo "Log file: $LOG_FILE"

case "$1" in
  stop)
    shutdown 2>&1 | tee -a $LOG_FILE && exit; ;;
  logs)
    tail -f $LOG_FILE;;
  *)
    connect 2>&1 | tee $LOG_FILE ;;
esac

