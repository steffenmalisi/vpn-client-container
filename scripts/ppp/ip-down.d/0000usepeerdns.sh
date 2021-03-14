#!/usr/bin/env bash

DNSMASQ_CONF=/etc/dnsmasq.d/0000usepeerdns.conf

# delete the file if it exists
if [ -e $DNSMASQ_CONF ]; then
  rm $DNSMASQ_CONF
fi

systemctl restart dnsmasq

exit 0