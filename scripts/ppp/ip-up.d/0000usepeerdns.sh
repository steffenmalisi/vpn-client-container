#!/usr/bin/env bash

. /home/ubuntu/.config/.net.cfg

# this variable is only set if the usepeerdns pppd option is being used
[ "$USEPEERDNS" ] || exit 0
[ -n "$VPN_DOMAINS" ] || exit 0

DNSMASQ_CONF=/etc/dnsmasq.d/0000usepeerdns.conf

# delete the file if it exists
if [ -e $DNSMASQ_CONF ]; then
  rm $DNSMASQ_CONF
fi

# and create a new one
touch $DNSMASQ_CONF

for domain in ${VPN_DOMAINS[@]}
do
  echo "server=/$domain/$DNS1" >> $DNSMASQ_CONF
done

systemctl restart dnsmasq

exit 0