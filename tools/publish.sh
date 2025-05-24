#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# Sign the artifacts, place them in a folder to be available on
# the local network and publish the docker image.
##################################################################

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

ARGUMENT_ERROR_MESSAGE="Valid common version numbers, LOCALVERSION and, optionally a CIP number. For example: ./publish.sh 4.4.302.16.1 -tinycore-560z 97"

if [ ! $# -ge 2 ]; then
  echo "$ARGUMENT_ERROR_MESSAGE"
  exit 1
fi

COMMON_VERSION_NUMBERS=$1
LOCALVERSION=$2

CIP_NUMBER=$3
if [ ! -z CIP_NUMBER ]; then
  if ! check_is_digit 1 $CIP_NUMBER; then
    echo "CIP_NUMBER is wrong: $CIP_NUMBER. For example, enter 97 if your tar name has something like 4.4.302-cip97."
    exit 2
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

if [ ! -z $CIP_NUMBER ]; then
  KERNEL_VERSION=$KERNEL_VERSION-cip$CIP_NUMBER
fi

KERNEL_ID=$KERNEL_VERSION$LOCALVERSION
RELEASE_VERSION=$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER
HOST_RELEASE_DIRECTORY=./release/$RELEASE_VERSION

if [ ! $HOST_RELEASE_DIRECTORY/alsa-modules-$KERNEL_ID.tcz ]; then
  echo "Please investigate why alsa-modules-$KERNEL_ID.tcz is missing."
  exit 7
fi

if [ ! $HOST_RELEASE_DIRECTORY/ipv6-netfilter-$KERNEL_ID.tcz ]; then
  echo "Please investigate why is ipv6-netfilter-$KERNEL_ID.tcz missing."
  exit 8
fi

if [ ! $HOST_RELEASE_DIRECTORY/net-modules-$KERNEL_ID.tcz ]; then
  echo "Please investigate why is net-modules-$KERNEL_ID.tcz missing."
  exit 9
fi

if [ ! $HOST_RELEASE_DIRECTORY/parport-modules-$KERNEL_ID.tcz ]; then
  echo "Please investigate why is parport-modules-$KERNEL_ID.tcz missing."
  exit 10
fi

if [ ! $HOST_RELEASE_DIRECTORY/pcmcia-modules-$KERNEL_ID.tcz ]; then
  echo "Please investigate why is pcmcia-modules-$KERNEL_ID.tcz missing."
  exit 11
fi

if [ ! $HOST_RELEASE_DIRECTORY/usb-modules-$KERNEL_ID.tcz ]; then
  echo "Please investigate why is usb-modules-$KERNEL_ID.tcz missing."
  exit 12
fi

if [ ! $HOST_RELEASE_DIRECTORY/wireless-$KERNEL_ID.tcz ]; then
  echo "Please investigate why is wireless-$KERNEL_ID.tcz missing."
  exit 13
fi

if [ ! $HOST_RELEASE_DIRECTORY/bzImage-$RELEASE_VERSION ]; then
  echo "Please investigate why is bzImage-$RELEASE_VERSION missing."
  exit 14
fi

if [ ! $HOST_RELEASE_DIRECTORY/core-$RELEASE_VERSION.gz ]; then
  echo "Please investigate why is core-$RELEASE_VERSION.gz missing."
  exit 15
fi

if [ ! ./configuration/network_directory ]; then
  echo "Please create the ./configuration/network_directory from the root directory of the git repo."
  exit 2
fi

if [ ! ./configuration/network_directory_owner ]; then
  echo "Please create the ./configuration/network_directory_owner from the root directory of the git repo."
  exit 2
fi

export HOST_NETWORK_DIRECTORY=$(cat ./configuration/network_directory)
export HOST_NETWORK_DIRECTORY_OWNER=$(cat ./configuration/network_directory_owner)

echo "Signing, making artifacts available on the local network, publishing to hub.docker.com..."

cd $HOST_RELEASE_DIRECTORY

gpg --detach-sign alsa-modules-$KERNEL_ID.tcz
gpg --detach-sign ipv6-netfilter-$KERNEL_ID.tcz
gpg --detach-sign net-modules-$KERNEL_ID.tcz
gpg --detach-sign parport-modules-$KERNEL_ID.tcz
gpg --detach-sign pcmcia-modules-$KERNEL_ID.tcz
gpg --detach-sign usb-modules-$KERNEL_ID.tcz
gpg --detach-sign wireless-$KERNEL_ID.tcz
gpg --detach-sign bzImage-$RELEASE_VERSION
gpg --detach-sign core-$RELEASE_VERSION.gz

sudo cp alsa-modules-$KERNEL_ID.tcz  $HOST_NETWORK_DIRECTORY
sudo cp ipv6-netfilter-$KERNEL_ID.tcz  $HOST_NETWORK_DIRECTORY
sudo cp net-modules-$KERNEL_ID.tcz  $HOST_NETWORK_DIRECTORY
sudo cp parport-modules-$KERNEL_ID.tcz  $HOST_NETWORK_DIRECTORY
sudo cp pcmcia-modules-$KERNEL_ID.tcz  $HOST_NETWORK_DIRECTORY
sudo cp usb-modules-$KERNEL_ID.tcz  $HOST_NETWORK_DIRECTORY
sudo cp wireless-$KERNEL_ID.tcz  $HOST_NETWORK_DIRECTORY
sudo cp bzImage-$RELEASE_VERSION  $HOST_NETWORK_DIRECTORY
sudo cp core-$RELEASE_VERSION.gz $HOST_NETWORK_DIRECTORY

sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/alsa-modules-$KERNEL_ID.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/ipv6-netfilter-$KERNEL_ID.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/net-modules-$KERNEL_ID.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/parport-modules-$KERNEL_ID.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/pcmcia-modules-$KERNEL_ID.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/usb-modules-$KERNEL_ID.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/wireless-$KERNEL_ID.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/bzImage-$RELEASE_VERSION
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/core-$RELEASE_VERSION.gz

sudo cp alsa-modules-$KERNEL_ID.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp ipv6-netfilter-$KERNEL_ID.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp net-modules-$KERNEL_ID.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp parport-modules-$KERNEL_ID.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp pcmcia-modules-$KERNEL_ID.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp usb-modules-$KERNEL_ID.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp wireless-$KERNEL_ID.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp bzImage-$RELEASE_VERSION.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp core-$RELEASE_VERSION.gz.md5.txt $HOST_NETWORK_DIRECTORY

sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/alsa-modules-$KERNEL_ID.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/ipv6-netfilter-$KERNEL_ID.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/net-modules-$KERNEL_ID.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/parport-modules-$KERNEL_ID.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/pcmcia-modules-$KERNEL_ID.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/usb-modules-$KERNEL_ID.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/wireless-$KERNEL_ID.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/bzImage-$RELEASE_VERSION.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/core-$RELEASE_VERSION.gz.md5.txt

echo "Push image to hub.docker.com? (y/n): "
read push_response

if [ "$push_response" = "y" ]; then
  sudo docker push linichotmailca/tcl-core-560z:$RELEASE_VERSION
  sudo docker push linichotmailca/tcl-core-560z:latest
fi

