#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# Sign the artifacts, place them in a folder to be available on
# the local network and publish the docker image.
##################################################################

BUILD_VERSION_ERROR_MESSAGE="Please enter a valid build version as the first parameter. For example 6.13.7.16.2."
if [ ! $# -eq 1 ]; then
  echo $BUILD_VERSION_ERROR_MESSAGE
  exit 6
fi
# Save the first parameter as the build version.
BUILD_VERSION=$1
# IFS is by default space, tab and newline. When 6.12.11.15.9 is entered, it is 1 parameter and in the first positional parameter.
# Set the Internal Field Separator to "." that way each digit of 6.12.11.15.9 will be separated in different variables.
OLD_IFS=$IFS
IFS="."
# Use set to reset the positional parameters.
set -- $BUILD_VERSION
echo $BUILD_VERSION
N1=$1
N2=$2
N3=$3
N4=$4
N5=$5
KERNEL_VERSION=$1.$2.$3
TINYCORE_ITERATION=$4.$5
# Display the values for tracking purposes.
echo "BUILD_VERSION=$BUILD_VERSION, N1=$N1, N2=$N2, N3=$N3, N4=$N4, N5=$N5, KERNEL_VERSION=$KERNEL_VERSION, TINYCORE_ITERATION=$TINYCORE_ITERATION"
# Check N1 to N5 are integers.
# Check if each part is a valid integer
n_number=1
for N in "$N1" "$N2" "$N3" "$N4" "$N5"; do
  non_digits=$(echo "$N" | sed 's/[0-9]//g')
  DIGIT_ERROR_MESSAGE="Digit number $n_number in $BUILD_VERSION is '$N' and is not an integer."
  if [ -n "$non_digits" ]; then
    echo "$DIGIT_ERROR_MESSAGE $BUILD_VERSION_ERROR_MESSAGE"
    exit $n_number
  fi
  if [ -z "$N" ]; then
    echo "$DIGIT_ERROR_MESSAGE $BUILD_VERSION_ERROR_MESSAGE"
    exit $n_number
  fi
  n_number=$((n_number+1))
done
KERNEL_VERSION=$N1.$N2.$N3
# Restore IFS otherwise all commands below will split parameters using dots and will fail.
IFS=$OLD_IFS

if [ ! release/$BUILD_VERSION/alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz ]; then
  echo "Please investigate why alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz is missing."
  exit 7
fi

if [ ! release/$BUILD_VERSION/ipv6-netfilter-$KERNEL_VERSION-tinycore-560z.tcz ]; then
  echo "Please investigate why is ipv6-netfilter-$KERNEL_VERSION-tinycore-560z.tcz missing."
  exit 8
fi

if [ ! release/$BUILD_VERSION/net-modules-$KERNEL_VERSION-tinycore-560z.tcz ]; then
  echo "Please investigate why is net-modules-$KERNEL_VERSION-tinycore-560z.tcz missing."
  exit 9
fi

if [ ! release/$BUILD_VERSION/parport-modules-$KERNEL_VERSION-tinycore-560z.tcz ]; then
  echo "Please investigate why is parport-modules-$KERNEL_VERSION-tinycore-560z.tcz missing."
  exit 10
fi

if [ ! release/$BUILD_VERSION/pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz ]; then
  echo "Please investigate why is pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz missing."
  exit 11
fi

if [ ! release/$BUILD_VERSION/usb-modules-$KERNEL_VERSION-tinycore-560z.tcz ]; then
  echo "Please investigate why is usb-modules-$KERNEL_VERSION-tinycore-560z.tcz missing."
  exit 12
fi

if [ ! release/$BUILD_VERSION/wireless-$KERNEL_VERSION-tinycore-560z.tcz ]; then
  echo "Please investigate why is wireless-$KERNEL_VERSION-tinycore-560z.tcz missing."
  exit 13
fi

if [ ! release/$BUILD_VERSION/bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION ]; then
  echo "Please investigate why is bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION missing."
  exit 14
fi

if [ ! release/$BUILD_VERSION/core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz ]; then
  echo "Please investigate why is core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz missing."
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

cd ./release/$BUILD_VERSION

gpg --detach-sign alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz 
gpg --detach-sign ipv6-netfilter-$KERNEL_VERSION-tinycore-560z.tcz 
gpg --detach-sign net-modules-$KERNEL_VERSION-tinycore-560z.tcz 
gpg --detach-sign parport-modules-$KERNEL_VERSION-tinycore-560z.tcz 
gpg --detach-sign pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz 
gpg --detach-sign usb-modules-$KERNEL_VERSION-tinycore-560z.tcz 
gpg --detach-sign wireless-$KERNEL_VERSION-tinycore-560z.tcz 
gpg --detach-sign bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION 
gpg --detach-sign core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz

sudo cp alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz  $HOST_NETWORK_DIRECTORY
sudo cp ipv6-netfilter-$KERNEL_VERSION-tinycore-560z.tcz  $HOST_NETWORK_DIRECTORY
sudo cp net-modules-$KERNEL_VERSION-tinycore-560z.tcz  $HOST_NETWORK_DIRECTORY
sudo cp parport-modules-$KERNEL_VERSION-tinycore-560z.tcz  $HOST_NETWORK_DIRECTORY
sudo cp pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz  $HOST_NETWORK_DIRECTORY
sudo cp usb-modules-$KERNEL_VERSION-tinycore-560z.tcz  $HOST_NETWORK_DIRECTORY
sudo cp wireless-$KERNEL_VERSION-tinycore-560z.tcz  $HOST_NETWORK_DIRECTORY
sudo cp bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION  $HOST_NETWORK_DIRECTORY
sudo cp core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz $HOST_NETWORK_DIRECTORY

sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/ipv6-netfilter-$KERNEL_VERSION-tinycore-560z.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/net-modules-$KERNEL_VERSION-tinycore-560z.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/parport-modules-$KERNEL_VERSION-tinycore-560z.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/usb-modules-$KERNEL_VERSION-tinycore-560z.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/wireless-$KERNEL_VERSION-tinycore-560z.tcz
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz

sudo cp alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp ipv6-netfilter-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp net-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp parport-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp usb-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp wireless-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION.md5.txt  $HOST_NETWORK_DIRECTORY
sudo cp core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz.md5.txt $HOST_NETWORK_DIRECTORY

sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/ipv6-netfilter-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/net-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/parport-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/usb-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/wireless-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION.md5.txt
sudo chown $HOST_NETWORK_DIRECTORY_OWNER:$HOST_NETWORK_DIRECTORY_OWNER $HOST_NETWORK_DIRECTORY/core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz.md5.txt

echo "Push image to hub.docker.com? (y/n): "
read push_response

if [ "$push_response" = "y" ]; then
  sudo docker push linichotmailca/tcl-core-560z:$BUILD_VERSION
  sudo docker push linichotmailca/tcl-core-560z:latest
fi

