#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# Choose an IP address that's not already in use
# on the LAN or you'll have conflicts.
##################################################################

sudo ifconfig eth0 192.168.0.57
sudo route add default gw 192.168.0.1
sudo echo "nameserver 1.1.1.1" > /etc/resolv.conf

