#!/usr/bin/env bash

sudo sysctl -wq net.ipv4.ip_forward=1
sudo iptables -A FORWARD -o ppp0 -i enp0s2 -s 192.168.0.0/16 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE
