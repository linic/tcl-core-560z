#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# I'm using a REALTEK 8152 USB to Ethernet adapter so usb modules
# need to be loaded first to detect the adapter.
##################################################################

tce-load -i usb-modules-6.12.11-tinycore-560z
tce-load -i net-modules-6.12.11-tinycore-560z

