#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# Package the core.gz with the modules matching the current
# linux kernel.
# Use the rootfs.gz in the cache if available.
##################################################################

set -e
trap 'echo "Error on line $LINENO"' ERR

HOME_TC=/home/tc
CACHE=$HOME_TC/cache
CORE_READY_FILES_PATH=$HOME_TC/core-ready
CORE_READY_MODULES_PATH=$CORE_READY_FILES_PATH/lib/modules
CORE_TEMP_PATH=$HOME_TC/coretmp
CORE_TEMP_MODULES_PATH=$CORE_TEMP_PATH/lib/modules
INSTALL_MOD_PATH=$HOME_TC/modules
ROOTFS_CACHE=$CACHE/rootfs
TOOLS=/home/tc/tools

ARGUMENT_ERROR_MESSAGE="RELEASE_VERSION, KERNEL_ID, KERNEL_NAME, CORE_GZ are needed. For example: ./package-core-gz.sh 5.10.240.16.1 5.10.240-tinycore-560z linux-5.10.240 rootfs.gz"
if [ ! $# -eq 4 ]; then
  echo "$ARGUMENT_ERROR_MESSAGE"
  exit 1
fi

RELEASE_VERSION=$1
KERNEL_ID=$2
KERNEL_NAME=$3
CORE_GZ=$4

echo "Packaging core.gz using arguments: $RELEASE_VERSION, $KERNEL_ID, $KERNEL_NAME"

RELEASE_DIRECTORY=$HOME_TC/release/$RELEASE_VERSION
mkdir -p $RELEASE_DIRECTORY

if [ -f $ROOTFS_CACHE/rootfs.gz ]; then
  echo "Using rootfs.gz from the cache."
  # Using the cache, it's possible to force the use of a custom rootfs.gz.
  # Getting, editing and unpacking the official core.gz as explained in
  # https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
  if [ -d $CORE_TEMP_PATH ]; then
    sudo rm -rf $CORE_TEMP_PATH
  fi
  mkdir -pv $CORE_TEMP_PATH
  cd $CORE_TEMP_PATH
  zcat $ROOTFS_CACHE/rootfs.gz | sudo cpio -i -H newc -d
  # Removing the official modules since they can't be used with our custom kernel
  if [ -d $CORE_TEMP_MODULES_PATH ]; then sudo rm -rf $CORE_TEMP_MODULES_PATH; fi
else
  echo "Getting $CORE_GZ from tinycorelinux.net..."
  # There are 2 ways to replace the modules in core.gz:
  # 1. get core.gz, unpack it and remove the modules since it is rootfs.gz + modules.gz
  # 2. get rootfs.gz directly
  # Note: for 16.0beta1, core.gz doesn't exist yet. So rootfs.gz must be used.
  # For release versions, core.gz exists and can be used. The code below works with both.
  # Getting core.gz for later
  cd $HOME_TC
  wget http://tinycorelinux.net/$TCL_VERSION/x86/$TCL_RELEASE_TYPE/distribution_files/$CORE_GZ
  wget http://tinycorelinux.net/$TCL_VERSION/x86/$TCL_RELEASE_TYPE/distribution_files/$CORE_GZ.md5.txt
  md5sum -c $CORE_GZ.md5.txt
  # Getting, editing and unpacking the official core.gz as explained in
  # https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
  mkdir $CORE_TEMP_PATH
  cd $CORE_TEMP_PATH
  zcat $HOME_TC/$CORE_GZ | sudo cpio -i -H newc -d
  # Removing the official modules since they can't be used with our custom kernel
  CORE_TEMP_MODULES_PATH=$CORE_TEMP_PATH/lib/modules
  if [ -d $CORE_TEMP_MODULES_PATH ]; then sudo rm -rf $CORE_TEMP_MODULES_PATH; fi
fi

# Copying the module files which are not in *modules-$KERNEL_ID.tcz files to core.gz.
sudo mkdir -p $CORE_TEMP_MODULES_PATH
if [ -d $CORE_READY_MODULES_PATH ]; then
  sudo mv $CORE_READY_MODULES_PATH/* $CORE_TEMP_MODULES_PATH/
  echo "Checking if something is left in $CORE_READY_MODULES_PATH"
  sudo ls $CORE_READY_MODULES_PATH
  echo "Nothing should be left here since it was moved to $CORE_TEMP_MODULES_PATH/"
fi

# create the kernel.tclocal
sudo $TOOLS/create-kernel-tclocal.sh $KERNEL_ID $CORE_TEMP_PATH

# Generate the custom core.gz file as explained in 
# https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
cd $CORE_TEMP_PATH
sudo find | sudo cpio -o -H newc | gzip -9 > $RELEASE_DIRECTORY/core-$RELEASE_VERSION.gz

