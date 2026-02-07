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

REQUIRED_ARGUMENTS="Common version numbers, LOCAL_VERSION, CORE_GZ, (optional) CIP number are required."
CALL_EXAMPLE="./make-bzImage-modules-tczs.sh 4.4.302.7.1 -tinycore-560z rootfs.gz 97"
ARGUMENT_ERROR_MESSAGE="$REQUIRED_ARGUMENTS For example: $CALL_EXAMPLE"

if [ ! $# -ge 3 ]; then
  echo $ARGUMENT_ERROR_MESSAGE
  exit 1
fi

COMMON_VERSION_NUMBERS=$1
LOCAL_VERSION=$2
CORE_GZ=$3

if [ $# -ge 4 ]; then
  CIP_NUMBER=$4
  if [ ! -z CIP_NUMBER ]; then
    if ! check_is_digit 1 $CIP_NUMBER; then
      echo "CIP_NUMBER is wrong: $CIP_NUMBER. For example, enter 97 if your tar name has something like 4.4.302-cip97."
      exit 4
    fi
  fi
fi

# IFS is by default space, tab and newline. When 6.12.11.15.9 is entered, it is 1 parameter and in the first positional parameter.
# Set the Internal Field Separator to "." that way each digit of 6.12.11.15.9 will be separated in different variables.
OLD_IFS=$IFS
IFS="."
# Use set to reset the positional parameters.
set -- $COMMON_VERSION_NUMBERS
# Check if each part is a valid integer
n_number=1
for N in "$1" "$2" "$3" "$4" "$5"; do
  if ! check_is_digit $n_number $N; then
    echo "$ARGUMENT_ERROR_MESSAGE"
    exit 5
  fi
  n_number=$((n_number+1))
done
# Restore IFS otherwise all commands below will split parameters using dots and will fail.
IFS=$OLD_IFS

KERNEL_VERSION=$1.$2.$3
TCL_MAJOR_VERSION_NUMBER=$4
ITERATION_NUMBER=$5

# Default to linux kernel project naming conventions.
KERNEL_BRANCH=v$1.x
KERNEL_NAME=linux-$KERNEL_VERSION
KERNEL_TAR=$KERNEL_NAME.tar.xz
KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/$KERNEL_BRANCH/$KERNEL_TAR

if [ ! -z $CIP_NUMBER ]; then
  KERNEL_VERSION=$KERNEL_VERSION-cip$CIP_NUMBER
  echo "$KERNEL_VERSION is maintained by CIP. Changing KERNEL_NAME, KERNEL_TAR, KERNEL_URL."
  KERNEL_NAME=linux-cip-$KERNEL_VERSION
  KERNEL_TAR=$KERNEL_NAME.tar.gz
  KERNEL_URL=https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git/snapshot/$KERNEL_TAR
fi
KERNEL_ID=$KERNEL_VERSION$LOCAL_VERSION
RELEASE_VERSION=$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER
RELEASE_DIRECTORY=$HOME_TC/release/$RELEASE_VERSION

ls -a $CACHE/$KERNEL_VERSION
ls -a $KERNEL_CONFIGS
ls -a $CS4237B_PATCHES
if [ ! -d $CACHE/$KERNEL_VERSION ]; then
  echo "Expected $CACHE/$KERNEL_VERSION to exist."
  exit 10
fi
mkdir -p $RELEASE_DIRECTORY
cp -v $KERNEL_CONFIGS/.config-$KERNEL_BRANCH $CACHE/$KERNEL_VERSION/.config
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
  echo "md5sum -c .config-$KERNEL_BRANCH.md5.txt didn't reveal a usable kernel already compiled with " \
    "this .config-$KERNEL_BRANCH file. Getting the kernel.tar.xz and building the kernel and modules."
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
  $TOOLS/pick-config.sh $KERNEL_BRANCH

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

