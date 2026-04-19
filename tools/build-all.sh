#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# The script checks all dependencies are available.
# It builds the docker image which builds the custom bzImage,
# core.gz, .tcz files and their .md5.txt files and copies them
# in a release/$1.$2 folder (for example release/6.12.11.15.9).
##################################################################

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

HOME_TC=/home/tc

REQUIRED_ARGUMENTS="VERSION_QUINTUPLET, TCL_RELEASE_TYPE, core.gz or rootfs.gz, LOCAL_VERSION, TCL_DOCKER_IMAGE_VERSION, (optional) CIP_NUMBER are required."
CALL_EXAMPLE="./build-all.sh 4.4.302.7.1 release rooftfs.gz -tinycore-560z 16.x 97"
ARGUMENT_ERROR_MESSAGE="$REQUIRED_ARGUMENTS For example: $CALL_EXAMPLE"

if [ $# -lt 5 ]; then
  echo "$ARGUMENT_ERROR_MESSAGE"
  exit 1
fi

VERSION_QUINTUPLET=$1
TCL_RELEASE_TYPE=$2
CORE_GZ=$3
LOCAL_VERSION=$4
TCL_DOCKER_IMAGE_VERSION=$5
CIP_NUMBER=$6

if [ "$TCL_RELEASE_TYPE" != "release" ] && [ "$TCL_RELEASE_TYPE" != "release_candidates" ]; then
  echo "The 2nd parameter should be either 'release' or 'release_candidates'."
  exit 2
fi
if [ "$CORE_GZ" != "core.gz" ] && [ "$CORE_GZ" != "rootfs.gz" ]; then
  echo "The 3rd parameter should be either 'core.gz' or 'rootfs.gz'."
  exit 3
fi
if ! quintuplet_separator "$VERSION_QUINTUPLET"; then
  echo "$ARGUMENT_ERROR_MESSAGE"
  exit 5
fi
if ! cip_number_check "$CIP_NUMBER"; then
  exit 4
fi

if [ ! -f Dockerfile ]; then
  echo "Please run this from the base folder of "\
    "https://github.com/linic/tcl-core-560z (Dockerfile missing)."
  exit 8
fi

resolve_kernel_urls "$CIP_NUMBER"
KERNEL_ID=$KERNEL_VERSION$LOCAL_VERSION
RELEASE_VERSION=$KERNEL_VERSION.$TCL_MAJOR.$ITERATION
RELEASE_DIRECTORY=$HOME_TC/release/$RELEASE_VERSION
HOST_RELEASE_DIRECTORY=./release/$RELEASE_VERSION

CACHE=$HOME_TC/cache/$KERNEL_VERSION
HOST_CACHE=`pwd`/cache/$KERNEL_VERSION
echo "HOST_CACHE=$HOST_CACHE"
mkdir -p $HOST_CACHE

if [ ! -f docker-compose.yml ] || ! grep -q "$KERNEL_URL" docker-compose.yml || ! grep -q "ITERATION_NUMBER=$ITERATION" docker-compose.yml || ! grep -q "KERNEL_ID=$KERNEL_ID" docker-compose.yml || ! grep -q "RELEASE_VERISON=$RELEASE_VERSION" docker-compose.yml || ! grep -q "TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION" docker-compose.yml; then
  echo "Did not find $KERNEL_URL or the ITERATION_NUMBER=$ITERATION or the KERNEL_ID=$KERNEL_ID or the TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION in docker-compose.yml. Rewriting docker-compose.yml."
  echo "services:\n"\
    " main:\n"\
    "   build:\n"\
    "     context: .\n"\
    "     args:\n"\
    "       - CORE_GZ=$CORE_GZ\n"\
    "       - CIP_NUMBER=$CIP_NUMBER\n"\
    "       - ITERATION_NUMBER=$ITERATION\n"\
    "       - KERNEL_BRANCH=$KERNEL_BRANCH\n"\
    "       - KERNEL_ID=$KERNEL_ID\n"\
    "       - KERNEL_NAME=$KERNEL_NAME\n"\
    "       - KERNEL_TAR=$KERNEL_TAR\n"\
    "       - KERNEL_URL=$KERNEL_URL\n"\
    "       - KERNEL_VERSION=$KERNEL_VERSION\n"\
    "       - LOCAL_VERSION=$LOCAL_VERSION\n"\
    "       - RELEASE_DIRECTORY=$RELEASE_DIRECTORY\n"\
    "       - RELEASE_VERSION=$RELEASE_VERSION\n"\
    "       - TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION\n"\
    "       - TCL_RELEASE_TYPE=$TCL_RELEASE_TYPE\n"\
    "       - TCL_VERSION=$TCL_MAJOR.x\n"\
    "       - VERSION_QUINTUPLET=$VERSION_QUINTUPLET\n"\
    "     dockerfile: Dockerfile\n"\
    "     tags:\n"\
    "       - linichotmailca/tcl-core-560z:$RELEASE_VERSION\n"\
    "       - linichotmailca/tcl-core-560z:latest\n" > docker-compose.yml
fi

echo "Requirements are met. Building and getting..."
echo "  alsa-modules-$KERNEL_ID.tcz"
echo "  net-modules-$KERNEL_ID.tcz"
echo "  parport-modules-$KERNEL_ID.tcz"
echo "  pcmcia-modules-$KERNEL_ID.tcz"
echo "  usb-modules-$KERNEL_ID.tcz"
echo "  bzImage-$RELEASE_VERSION"
echo "  core-$RELEASE_VERSION.gz"

if sudo docker compose --progress=plain -f docker-compose.yml build; then
  echo "Kernel and TCZs built successfully."
else
  echo "Kernel and TCZs build failure!"
  exit 21
fi

sudo docker compose --progress=plain -f docker-compose.yml up --detach

mkdir -p $HOST_RELEASE_DIRECTORY
cd $HOST_RELEASE_DIRECTORY

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/alsa-modules-$KERNEL_ID.tcz ./
md5sum ./alsa-modules-$KERNEL_ID.tcz > ./alsa-modules-$KERNEL_ID.tcz.md5.txt
cat ./alsa-modules-$KERNEL_ID.tcz.md5.txt
sudo docker cp tcl-core-560z-main-1:$CACHE/alsa-modules-$KERNEL_ID.tcz $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/ipv6-netfilter-$KERNEL_ID.tcz ./
md5sum ./ipv6-netfilter-$KERNEL_ID.tcz > ./ipv6-netfilter-$KERNEL_ID.tcz.md5.txt
cat ./ipv6-netfilter-$KERNEL_ID.tcz.md5.txt
sudo docker cp tcl-core-560z-main-1:$CACHE/ipv6-netfilter-$KERNEL_ID.tcz $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/net-modules-$KERNEL_ID.tcz ./
md5sum ./net-modules-$KERNEL_ID.tcz > ./net-modules-$KERNEL_ID.tcz.md5.txt
cat ./net-modules-$KERNEL_ID.tcz.md5.txt
sudo docker cp tcl-core-560z-main-1:$CACHE/net-modules-$KERNEL_ID.tcz $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/parport-modules-$KERNEL_ID.tcz ./
md5sum ./parport-modules-$KERNEL_ID.tcz > ./parport-modules-$KERNEL_ID.tcz.md5.txt
cat ./parport-modules-$KERNEL_ID.tcz.md5.txt
sudo docker cp tcl-core-560z-main-1:$CACHE/parport-modules-$KERNEL_ID.tcz $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/pcmcia-modules-$KERNEL_ID.tcz ./
md5sum ./pcmcia-modules-$KERNEL_ID.tcz > ./pcmcia-modules-$KERNEL_ID.tcz.md5.txt
cat ./pcmcia-modules-$KERNEL_ID.tcz.md5.txt
sudo docker cp tcl-core-560z-main-1:$CACHE/pcmcia-modules-$KERNEL_ID.tcz $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/usb-modules-$KERNEL_ID.tcz ./
md5sum ./usb-modules-$KERNEL_ID.tcz > ./usb-modules-$KERNEL_ID.tcz.md5.txt
cat ./usb-modules-$KERNEL_ID.tcz.md5.txt
sudo docker cp tcl-core-560z-main-1:$CACHE/usb-modules-$KERNEL_ID.tcz $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/wireless-$KERNEL_ID.tcz ./
md5sum ./wireless-$KERNEL_ID.tcz > ./wireless-$KERNEL_ID.tcz.md5.txt
cat ./wireless-$KERNEL_ID.tcz.md5.txt
sudo docker cp tcl-core-560z-main-1:$CACHE/wireless-$KERNEL_ID.tcz $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/bzImage-$RELEASE_VERSION ./
md5sum ./bzImage-$RELEASE_VERSION > ./bzImage-$RELEASE_VERSION.md5.txt
cat ./bzImage-$RELEASE_VERSION.md5.txt
sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/bzImage-$RELEASE_VERSION $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/core-$RELEASE_VERSION.gz ./
md5sum ./core-$RELEASE_VERSION.gz > ./core-$RELEASE_VERSION.gz.md5.txt
cat ./core-$RELEASE_VERSION.gz.md5.txt
sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/core-$RELEASE_VERSION.gz $HOST_CACHE/

sudo docker cp tcl-core-560z-main-1:$CACHE/.config.md5.txt $HOST_CACHE/

cd ../..
sudo docker compose --progress=plain -f docker-compose.yml down

