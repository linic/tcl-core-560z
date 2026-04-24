#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# Check if the kernel and the tczs are in the cache before
# building them. If they're not in the cache, build them.
##################################################################

set -e
trap 'echo "Error on line $LINENO"' ERR

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

HOME_TC=/home/tc
CACHE=$HOME_TC/cache
KERNEL_CONFIGS=$HOME_TC/kernel_configs
CS4237B_PATCHES=$HOME_TC/cs4237b
TOOLS=$HOME_TC/tools

REQUIRED_ARGUMENTS="VERSION_QUINTUPLET, LOCAL_VERSION, CORE_GZ, (optional) CIP_NUMBER are required."
CALL_EXAMPLE="./make-bzImage-modules-tczs.sh 4.4.302.7.1 -tinycore-560z rootfs.gz 97"
ARGUMENT_ERROR_MESSAGE="$REQUIRED_ARGUMENTS For example: $CALL_EXAMPLE"

if [ $# -lt 3 ]; then
  echo "$ARGUMENT_ERROR_MESSAGE"
  exit 1
fi

VERSION_QUINTUPLET=$1
LOCAL_VERSION=$2
CORE_GZ=$3
CIP_NUMBER=$4

if ! quintuplet_separator "$VERSION_QUINTUPLET"; then
  echo "$ARGUMENT_ERROR_MESSAGE"
  exit 5
fi
if ! cip_number_check "$CIP_NUMBER"; then
  exit 4
fi

resolve_kernel_urls "$CIP_NUMBER"
if ! get_suffix "$MAJOR.$MINOR.$PATCH"; then
  echo "Cannot determine config suffix for $MAJOR.$MINOR.$PATCH"; exit 1
fi

KERNEL_ID=$KERNEL_VERSION$LOCAL_VERSION
RELEASE_VERSION=$KERNEL_VERSION.$TCL_MAJOR.$ITERATION
RELEASE_DIRECTORY=$HOME_TC/release/$RELEASE_VERSION

ls -a $CACHE/$KERNEL_VERSION
ls -a $KERNEL_CONFIGS
ls -a $CS4237B_PATCHES
if [ ! -d $CACHE/$KERNEL_VERSION ]; then
  echo "Expected $CACHE/$KERNEL_VERSION to exist."
  exit 10
fi
mkdir -p $RELEASE_DIRECTORY
cp -v $KERNEL_CONFIGS/.config-$SUFFIX $CACHE/$KERNEL_VERSION/.config
cd $CACHE/$KERNEL_VERSION
if md5sum -c $CACHE/$KERNEL_VERSION/.config.md5.txt; then
  echo "$KERNEL_VERSION is available from the $CACHE/$KERNEL_VERSION/"
  ln $CACHE/$KERNEL_VERSION/bzImage-$KERNEL_VERSION $RELEASE_DIRECTORY/bzImage-$RELEASE_VERSION
  ln $CACHE/$KERNEL_VERSION/alsa-modules-$KERNEL_ID.tcz $RELEASE_DIRECTORY/alsa-modules-$KERNEL_ID.tcz
  ln $CACHE/$KERNEL_VERSION/ipv6-netfilter-$KERNEL_ID.tcz $RELEASE_DIRECTORY/ipv6-netfilter-$KERNEL_ID.tcz
  ln $CACHE/$KERNEL_VERSION/net-modules-$KERNEL_ID.tcz $RELEASE_DIRECTORY/net-modules-$KERNEL_ID.tcz
  ln $CACHE/$KERNEL_VERSION/parport-modules-$KERNEL_ID.tcz $RELEASE_DIRECTORY/parport-modules-$KERNEL_ID.tcz
  ln $CACHE/$KERNEL_VERSION/pcmcia-modules-$KERNEL_ID.tcz $RELEASE_DIRECTORY/pcmcia-modules-$KERNEL_ID.tcz
  ln $CACHE/$KERNEL_VERSION/usb-modules-$KERNEL_ID.tcz $RELEASE_DIRECTORY/usb-modules-$KERNEL_ID.tcz
  ln $CACHE/$KERNEL_VERSION/wireless-$KERNEL_ID.tcz $RELEASE_DIRECTORY/wireless-$KERNEL_ID.tcz
else
  echo "md5sum -c $CACHE/$KERNEL_VERSION/.config.md5.txt didn't reveal a usable kernel already compiled with " \
    "this .config-$SUFFIX file. Getting the kernel.tar.xz and building the kernel and modules."
  # Getting kernel.tar.xz or kernel.tar.gz
  cd $HOME_TC
  curl --remote-name $KERNEL_URL
  tar x -f $KERNEL_TAR
  # Making the kernel, the modules and installing them
  KERNEL_SOURCE_PATH=$HOME_TC/$KERNEL_NAME
  cd $KERNEL_SOURCE_PATH
  pwd
  if mv $KERNEL_CONFIGS/.config* .; then
    echo "correctly moved kernel configs."
  else
    echo "failed to move kernel configs."
    exit 67
  fi
  $TOOLS/pick-config.sh $KERNEL_VERSION

  mv $CS4237B_PATCHES/* .
  $TOOLS/pick-patches.sh $KERNEL_VERSION
  $TOOLS/patch-cs4236.sh
  make oldconfig
  make kernelrelease
  # Make the kernel
  echo "make bzImage...."
  make bzImage > make.bzImage.log.txt 2>&1
  # Copying the bzImage which is the kernel
  cp $KERNEL_SOURCE_PATH/arch/x86/boot/bzImage $RELEASE_DIRECTORY/bzImage-$RELEASE_VERSION
  # Make the modules
  echo "make modules...."
  #make modules > make.modules.log.txt 2>&1
  if make modules; then
    echo "Modules were made successfully."
    $TOOLS/build-modules-tcz.sh $RELEASE_VERSION $KERNEL_ID $KERNEL_NAME
  else
    echo "No modules were made. Check the logs to see if that is normal."
    $TOOLS/build-modules-tcz.sh $RELEASE_VERSION $KERNEL_ID $KERNEL_NAME stubs
  fi
  # If there where files built from a previous .config file in the cache, they need to be removed.
  if [ -d $CACHE/$KERNEL_VERSION ]; then
    rm -rv $CACHE/$KERNEL_VERSION
  fi
  mkdir -p $CACHE/$KERNEL_VERSION
  ln $RELEASE_DIRECTORY/bzImage-$RELEASE_VERSION $CACHE/$KERNEL_VERSION/bzImage-$KERNEL_VERSION
  ln $RELEASE_DIRECTORY/alsa-modules-$KERNEL_ID.tcz $CACHE/$KERNEL_VERSION/alsa-modules-$KERNEL_ID.tcz
  ln $RELEASE_DIRECTORY/ipv6-netfilter-$KERNEL_ID.tcz $CACHE/$KERNEL_VERSION/ipv6-netfilter-$KERNEL_ID.tcz
  ln $RELEASE_DIRECTORY/net-modules-$KERNEL_ID.tcz $CACHE/$KERNEL_VERSION/net-modules-$KERNEL_ID.tcz
  ln $RELEASE_DIRECTORY/parport-modules-$KERNEL_ID.tcz $CACHE/$KERNEL_VERSION/parport-modules-$KERNEL_ID.tcz
  ln $RELEASE_DIRECTORY/pcmcia-modules-$KERNEL_ID.tcz $CACHE/$KERNEL_VERSION/pcmcia-modules-$KERNEL_ID.tcz
  ln $RELEASE_DIRECTORY/usb-modules-$KERNEL_ID.tcz $CACHE/$KERNEL_VERSION/usb-modules-$KERNEL_ID.tcz
  ln $RELEASE_DIRECTORY/wireless-$KERNEL_ID.tcz $CACHE/$KERNEL_VERSION/wireless-$KERNEL_ID.tcz

  # Put the md5 of the .config in the cache to know how the bzImage and modules were compiled.
  cp $KERNEL_SOURCE_PATH/.config $CACHE/$KERNEL_VERSION/.config
fi

$TOOLS/package-core-gz.sh $RELEASE_VERSION $KERNEL_ID $KERNEL_NAME $CORE_GZ
# Important to generate the md5sum only after core.gz has been packaged because it checks if the config
# in the cache matches the current config and if so, then it uses the modules from the core.gz in the cache.
cd $CACHE/$KERNEL_VERSION
md5sum .config > .config.md5.txt
rm -v .config
echo "Here is what's in the release directory $RELEASE_DIRECTORY:"
ls -larth $RELEASE_DIRECTORY
echo "make-bzImage-modules-tczs.sh should have completed successfully at this point."

