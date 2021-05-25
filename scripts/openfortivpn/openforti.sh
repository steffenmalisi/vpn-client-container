#!/bin/bash

. $HOME/.config/.openforti.cfg

LOG_FILE="/home/ubuntu/log/openforti.log"
VERBOSE=false
while getopts ':v' option; do
  case "$option" in
    v) VERBOSE=true ;;
  esac
done

COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_DEFAULT="\e[39m"
RESET_CONSOLE_LINE="\r\033[K"

function log() {
  echo "[$$] $(date '+%F %T:%N') $1 $2" >> $LOG_FILE
}

function write_connection_config() {
  sudo mkdir -p /etc/ppp/peers
  sudo bash -c "echo $CONNECT_CONFIG > /etc/ppp/peers/$CONNECTION_NAME"
}

function read_password() {
  case $PASSWORD in
    viastdin)
      read -s -p "Enter VPN password for ${USERNAME}: " PASSWORD
      echo -en "$RESET_CONSOLE_LINE"
      ;;
    *)
      echo -e "$COLOR_RED"
      echo "You are storing your password in the config file. You should only do this for testing purposes"
      echo -e "$COLOR_DEFAULT"
      ;;
  esac
}

function establish_connection() {
  log "DEBUG" "Establishing openforti connection for ${USERNAME} to ${VPN_GW}"
  if [ "$VERBOSE" = "true" ]; then
    echo $PASSWORD | sudo openfortivpn "${VPN_GW}" -u "${USERNAME}" --trusted-cert "${GWCERT_HASH}" --no-dns --pppd-call="${CONNECTION_NAME}" --pppd-log "${LOG_FILE}" -vvv >> $LOG_FILE 2>&1 &
  else
    echo $PASSWORD | sudo openfortivpn "${VPN_GW}" -u "${USERNAME}" --trusted-cert "${GWCERT_HASH}" --no-dns --pppd-call="${CONNECTION_NAME}" >> $LOG_FILE 2>&1 &
  fi
}

function second_factor() {
  echo -n "You may now have to check your second authentication factor"
  sleep 10;
  echo -en "$RESET_CONSOLE_LINE"
}

function configure_nat(){
  . /opt/nat/nat-init.sh
  log "DEBUG" "NAT configured"
}

function close_connection() {
  sudo pkill -SIGINT openfortivpn
  log "DEBUG" "Openfortivpn connection closed"
}

function flush_dns () {
  sudo systemctl restart dnsmasq
  log "DEBUG" "Container DNS flushed"
}

function connect(){
  rm -f $LOG_FILE
  shutdown
  log "DEBUG" "Establishing new connection"
  write_connection_config
  read_password
  establish_connection
  second_factor
  configure_nat
}

function shutdown() {
  log "DEBUG" "Shutting down existing connection"
  close_connection
	flush_dns
}

function get_status(){
  count=$(grep "Tunnel is up and running." $LOG_FILE | wc -l)
  if [ $count -eq 1 ]; then
    exit 0
  else
    exit 1
  fi
}

trap "shutdown && exit;" SIGINT SIGTERM

case "$1" in
  stop)
    shutdown && exit ;;
  status)
    get_status ;;
  logs)
    tail -f $LOG_FILE ;;
  *)
    connect ;;
esac

