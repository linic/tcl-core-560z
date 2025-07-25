#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# Build the modules.tcz files.
##################################################################

set -e
trap 'echo "Error on line $LINENO"' ERR

HOME_TC=/home/tc
CACHE=$HOME_TC/cache
CORE_READY_FILES_PATH=$HOME_TC/core-ready
CORE_READY_MODULES_PATH=$CORE_READY_FILES_PATH/lib/modules
INSTALL_MOD_PATH=$HOME_TC/modules
ROOTFS_CACHE=$CACHE/rootfs
TOOLS=/home/tc/tools

ARGUMENT_ERROR_MESSAGE="RELEASE_VERSION, KERNEL_ID, KERNEL_NAME are needed. For example: ./build-modules-tcz.sh 4.4.302-cip97.16.1 4.4.302-cip97-tinycore-560z linux-cip-4.4.302-cip97"
if [ ! $# -ge 3 ]; then
  echo "$ARGUMENT_ERROR_MESSAGE"
  exit 1
fi

RELEASE_VERSION=$1
KERNEL_ID=$2
KERNEL_NAME=$3

if [ $# -eq 4 ]; then
  EMPTY=$4
  echo "Building .tcz with readme files in them because there are no modules to package."
fi

echo "Building modules.tcz files using arguments: $RELEASE_VERSION, $KERNEL_ID, $KERNEL_NAME"

RELEASE_DIRECTORY=$HOME_TC/release/$RELEASE_VERSION
mkdir -p $RELEASE_DIRECTORY

cd $HOME_TC/$KERNEL_NAME

if [ -z EMPTY ]; then
  echo "Modules exist. Running make modules_install..."
  mkdir $INSTALL_MOD_PATH
  make INSTALL_MOD_PATH=$INSTALL_MOD_PATH modules_install

  # Arranging the custom built modules which will work with the customer kernel.
  # This is ultimately for core.gz as explained in
  # https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
  if [ ! -d $CORE_READY_MODULES_PATH ]; then sudo mkdir -p $CORE_READY_MODULES_PATH; fi
  ls $INSTALL_MOD_PATH/lib/modules/
  sudo cp -rv $INSTALL_MOD_PATH/lib/modules/$KERNEL_ID $CORE_READY_MODULES_PATH/

  # Let's compress the modules with gzip and advdef since it is like that in the official core.gz
  cd $CORE_READY_MODULES_PATH/$KERNEL_ID
  sudo $TOOLS/compress-modules.sh

  # edit modules.* files since they refer to the old .ko file and not the .ko.gz and won't load otherwise.
  sudo $TOOLS/edit-modules-dep-order.sh

  # source and build are there by default, but they're not needed
  if [ -d "source" ]; then sudo rm source; fi
  sudo rm build
fi

# Extracting the sound files to create the equivalent alsa-modules-KERNEL.tcz file.
cd $RELEASE_DIRECTORY
ALSA_TCZ_NAME=alsa-modules-$KERNEL_ID
ALSA_TCZ=$ALSA_TCZ_NAME.tcz
SOUND_INSTALL_PATH=$ALSA_TCZ_NAME/usr/local/lib/modules/$KERNEL_ID/kernel/sound
SOUND_MODULES_SOURCE=$CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/sound
mkdir -p $SOUND_INSTALL_PATH
# Move the sound modules from core since we'll have them in the alsa-modules-KERNEL.tcz
if [ -d $SOUND_MODULES_SOURCE ]; then
  sudo mv $SOUND_MODULES_SOURCE $SOUND_INSTALL_PATH
else
  echo "No $SOUND_MODULES_SOURCE. Modules should be built-in the kernel. This tcz is there for compatibility with other .tcz.dep." >> $ALSA_TCZ_NAME/readme-$ALSA_TCZ.txt
fi
mksquashfs $ALSA_TCZ_NAME $ALSA_TCZ > $ALSA_TCZ.mksquashfs-output.txt 2>&1
unsquashfs -l $ALSA_TCZ > $ALSA_TCZ.list.txt 2>&1

# Extracting the wireless files to create wireless-KERNEL.tcz file.
WIRELESS_TCZ_NAME=wireless-$KERNEL_ID
WIRELESS_TCZ=$WIRELESS_TCZ_NAME.tcz
DRIVERS_WIRELESS_INSTALL_PATH=$WIRELESS_TCZ_NAME/usr/local/lib/modules/$KERNEL_ID/kernel/drivers/net/wireless
DRIVERS_WIRELESS_SOURCE=$CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/net/wireless
mkdir -p $DRIVERS_WIRELESS_INSTALL_PATH
# Move the net/wireless modules from core since we'll have them in the wireless-KERNEL.tcz
if [ -d $DRIVERS_WIRELESS_SOURCE ]; then
  sudo mv $DRIVERS_WIRELESS_SOURCE $DRIVERS_WIRELESS_INSTALL_PATH
else
  echo "No $DRIVERS_WIRELESS_SOURCE. Modules should be built-in the kernel. This tcz is there for compatibility with other .tcz.dep." >> $WIRELESS_TCZ_NAME/readme-$WIRELESS_TCZ.txt
fi
mksquashfs $WIRELESS_TCZ_NAME $WIRELESS_TCZ > $WIRELESS_TCZ.mksquashfs-output.txt 2>&1
unsquashfs -l $WIRELESS_TCZ > $WIRELESS_TCZ.list.txt 2>&1

# Extracting the ipv6 and netfilter files to create ipv6-netfilter-KERNEL.tcz file.
IPV6_NETFILTER_TCZ_NAME=ipv6-netfilter-$KERNEL_ID
IPV6_NETFILTER_TCZ=$IPV6_NETFILTER_TCZ_NAME.tcz
IPV6_NETFILTER_INSTALL_PATH=$IPV6_NETFILTER_TCZ_NAME/usr/local/lib/modules/$KERNEL_ID/kernel/net
IPV4_NETFILTER_MODULES_SOURCE=$CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/net/ipv4/netfilter
IPV4_NETFILTER_MODULES_DESTINATION=$IPV6_NETFILTER_INSTALL_PATH/ipv4/netfilter
NETFILTER_MODULES_SOURCE=$CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/net/netfilter
NETFILTER_MODULES_DESTINATION=$IPV6_NETFILTER_INSTALL_PATH/netfilter
IPV6_MODULES_SOURCE=$CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/net/ipv6
IPV6_MODULES_DESTINATION=$IPV6_NETFILTER_INSTALL_PATH/ipv6
mkdir -p $IPV6_NETFILTER_INSTALL_PATH
mkdir -p $IPV6_NETFILTER_INSTALL_PATH/ipv4/netfilter
mkdir -p $IPV6_NETFILTER_INSTALL_PATH/ipv6
mkdir -p $IPV6_NETFILTER_INSTALL_PATH/netfilter
# Move the net/ipv4/netfilter, net/ipv6, net/netfilter modules from core since we'll have them in the ipv6-netfilter-KERNEL.tcz
if [ -d $IPV4_NETFILTER_MODULES_SOURCE ]; then
  sudo mv $IPV4_NETFILTER_MODULES_SOURCE $IPV4_NETFILTER_MODULES_DESTINATION
else
  echo "No $IPV4_NETFILTER_MODULES_SOURCE" >> $IPV4_NETFILTER_MODULES_DESTINATION/readme.txt
fi
if [ -d $NETFILTER_MODULES_SOURCE ]; then
  sudo mv $NETFILTER_MODULES_SOURCE $NETFILTER_MODULES_DESTINATION
else
  echo "No $NETFILTER_MODULES_SOURCE" >> $NETFILTER_MODULES_DESTINATION/readme.txt
fi
if [ -d $IPV6_MODULES_SOURCE ]; then
  sudo mv $IPV6_MODULES_SOURCE $IPV6_MODULES_DESTINATION
else
  echo "No $IPV6_MODULES_SOURCE" >> $IPV6_MODULES_DESTINATION/readme.txt
fi
mksquashfs $IPV6_NETFILTER_TCZ_NAME $IPV6_NETFILTER_TCZ > $IPV6_NETFILTER_TCZ.mksquashfs-output.txt 2>&1
unsquashfs -l $IPV6_NETFILTER_TCZ > $IPV6_NETFILTER_TCZ.list.txt 2>&1

# Extracting the net files to create net-modules-KERNEL.tcz file.
NET_TCZ_NAME=net-modules-$KERNEL_ID
NET_TCZ=$NET_TCZ_NAME.tcz
NET_INSTALL_PATH=$NET_TCZ_NAME/usr/local/lib/modules/$KERNEL_ID/kernel/net
DRIVERS_NET_INSTALL_PATH=$NET_TCZ_NAME/usr/local/lib/modules/$KERNEL_ID/kernel/drivers/net
mkdir -p $NET_INSTALL_PATH
mkdir -p $DRIVERS_NET_INSTALL_PATH
# Move the net and drivers/net modules from core since we'll have them in the net-modules-KERNEL.tcz
if [ -d $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/net ]; then
  sudo mv $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/net $NET_INSTALL_PATH
else
  echo "No $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/net" >> $NET_INSTALL_PATH/readme.txt
fi
if [ -d $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/net ]; then
  sudo mv $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/net $DRIVERS_NET_INSTALL_PATH
else
  echo "No $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/net" >> $DRIVERS_NET_INSTALL_PATH/readme.txt
fi
mksquashfs $NET_TCZ_NAME $NET_TCZ > $NET_TCZ.mksquashfs-output.txt 2>&1
unsquashfs -l $NET_TCZ > $NET_TCZ.list.txt 2>&1

# Extracting the drivers/usb files to create usb-modules-KERNEL.tcz file.
USB_TCZ_NAME=usb-modules-$KERNEL_ID
USB_TCZ=$USB_TCZ_NAME.tcz
USB_INSTALL_PATH=$USB_TCZ_NAME/usr/local/lib/modules/$KERNEL_ID/kernel/drivers/usb
mkdir -p $USB_INSTALL_PATH
# Move the kernel/drivers/usb modules from core since we'll have them in the usb-modules-KERNEL.tcz
if [ -d $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/usb ]; then
  sudo mv $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/usb $USB_INSTALL_PATH
else
  echo "No $CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/usb. Modules should be built-in the kernel. This tcz is there for compatibility with other .tcz.dep." >> $USB_TCZ_NAME/readme-$USB_TCZ.txt
fi
mksquashfs $USB_TCZ_NAME $USB_TCZ > $USB_TCZ.mksquashfs-output.txt 2>&1
unsquashfs -l $USB_TCZ > $USB_TCZ.list.txt 2>&1

# Extracting the drivers/pcmcia files to create pcmcia-modules-KERNEL.tcz file.
PCMCIA_TCZ_NAME=pcmcia-modules-$KERNEL_ID
PCMCIA_TCZ=$PCMCIA_TCZ_NAME.tcz
PCMCIA_INSTALL_PATH=$PCMCIA_TCZ_NAME/usr/local/lib/modules/$KERNEL_ID/kernel/drivers/pcmcia
PCMCIA_MODULES_SOURCE=$CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/pcmcia
mkdir -p $PCMCIA_INSTALL_PATH
# Move the kernel/drivers/pcmcia modules from core since we'll have them in the pcmcia-modules-KERNEL.tcz
if [ -d $PCMCIA_MODULES_SOURCE ]; then
  sudo mv $PCMCIA_MODULES_SOURCE $PCMCIA_INSTALL_PATH
else
  echo "No $PCMCIA_MODULES_SOURCE. Modules should be built-in the kernel. This tcz is there for compatibility with other .tcz.dep." >> $PCMCIA_TCZ_NAME/readme-$PCMCIA_TCZ.txt
fi
mksquashfs $PCMCIA_TCZ_NAME $PCMCIA_TCZ > $PCMCIA_TCZ.mksquashfs-output.txt 2>&1
unsquashfs -l $PCMCIA_TCZ > $PCMCIA_TCZ.list.txt 2>&1

# Extracting the drivers/parport files to create parport-modules-KERNEL.tcz file.
PARPORT_TCZ_NAME=parport-modules-$KERNEL_ID
PARPORT_TCZ=$PARPORT_TCZ_NAME.tcz
PARPORT_INSTALL_PATH=$PARPORT_TCZ_NAME/usr/local/lib/modules/$KERNEL_ID/kernel/drivers/parport
PARPORT_MODULES_SOURCE=$CORE_READY_MODULES_PATH/$KERNEL_ID/kernel/drivers/parport
mkdir -p $PARPORT_INSTALL_PATH
# Move the kernel/drivers/parport modules from core since we'll have them in the parport-modules-KERNEL.tcz
if [ -d $PARPORT_MODULES_SOURCE ]; then
  sudo mv $PARPORT_MODULES_SOURCE $PARPORT_INSTALL_PATH
else
  echo "No $PARPORT_MODULES_SOURCE. Modules should be built-in the kernel. This tcz is there for compatibility with other .tcz.dep." >> $PARPORT_TCZ_NAME/readme-$PARPORT_TCZ.txt
fi
mksquashfs $PARPORT_TCZ_NAME $PARPORT_TCZ > $PARPORT_TCZ.mksquashfs-output.txt 2>&1
unsquashfs -l $PARPORT_TCZ > $PARPORT_TCZ.list.txt 2>&1

