#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# This script is useful when moving to a new version of tinycore.
# For example, before moving from 15.x to 16.0beta1, copy the
# .tcz files in /home/tc/tc15. Then, get the new kernel, core.gz
# modify the extlinux.conf and reboot. After reboot, install your
# extensions again and you'll get the extensions from the new
# release.
##################################################################

if [ ! $# -eq 1 ]; then
  echo "Please enter a folder name for backing up the .tcz files. Example: prepare-upgrade.sh tc16"
  exit 1
fi

BACKUP_DIRECTORY=$1

mkdir -p $BACKUP_DIRECTORY
mv -v /mnt/sda3/tce/optional/* $BACKUP_DIRECTORY

# I found that these can often be reused between TCL versions.
# I'm using the one from TCL 14.x successfully with TCL 15.x and 16.x
cp $BACKUP_DIRECTORY/mylocale.tcz* /mnt/sda3/tce/optional/
cp $BACKUP_DIRECTORY/kmaps.tcz* /mnt/sda3/tce/optional/

