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

REQUIRED_ARGUMENTS="VERSION_QUINTUPLET, TCL_RELEASE_TYPE, core.gz or rootfs.gz, LOCALVERSION, TCL_DOCKER_IMAGE_VERSION, (optional) CIP_NUMBER are required."
CALL_EXAMPLE="./build-all.sh 4.4.302.7.1 release rooftfs.gz -tinycore-560z 16.x 97"
ARGUMENT_ERROR_MESSAGE="$REQUIRED_ARGUMENTS For example: $CALL_EXAMPLE"

if [ ! $# -ge 5 ]; then
  echo $ARGUMENT_ERROR_MESSAGE
  exit 1
fi

VERSION_QUINTUPLET=$1

TCL_RELEASE_TYPE=$2
if [ $TCL_RELEASE_TYPE != "release" ] && [ $TCL_RELEASE_TYPE != "release_candidates" ]; then
  echo "The 2nd parameter should be either 'release' or 'release_candidates'."
  exit 2
fi

CORE_GZ=$3
if [ $CORE_GZ != "core.gz" ] && [ $CORE_GZ != "rootfs.gz" ]; then
  echo "The 3rd parameter should be either 'core.gz' or 'rootfs.gz'."
  exit 3
fi

LOCALVERSION=$4

TCL_DOCKER_IMAGE_VERSION=$5

CIP_NUMBER=$6
if [ ! -z CIP_NUMBER ]; then
  if ! check_is_digit 1 $CIP_NUMBER; then
    echo "CIP_NUMBER is wrong: $CIP_NUMBER. For example, enter 97 if your tar name has something like 4.4.302-cip97."
    exit 4
  fi
fi

# IFS is by default space, tab and newline. When 6.12.11.15.9 is entered, it is 1 parameter and in the first positional parameter.
# Set the Internal Field Separator to "." that way each digit of 6.12.11.15.9 will be separated in different variables.
OLD_IFS=$IFS
IFS="."
# Use set to reset the positional parameters.
set -- $VERSION_QUINTUPLET
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

if [ ! .config ] || [ ! .config-v5.x ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since .config and "\
    ".config-v5.x are required."
  exit 7
fi

if [ ! Dockerfile ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since Dockerfile is "\
    "required."
  exit 8
fi

if [ ! echo_sleep ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: echo_sleep"
  exit 10
fi

if [ ! create-kernel.tclocal.sh ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: create-kernel.tclocal.sh"
  exit 11
fi

if [ ! compress_modules.sh ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: compress_modules.sh"
  exit 12
fi

if [ ! edit-modules.dep.order.sh ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: edit-modules.dep.order.sh"
  exit 13
fi

if [ ! cs4237b/sound/isa/cs423x/cs4236.c ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: cs4237b/sound/isa/cs423x/cs4236.c"
  exit 14
fi

if [ ! cs4237b/sound/isa/cs423x/cs4236_lib.c ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: cs4237b/sound/isa/cs423x/cs4236_lib.c"
  exit 15
fi

if [ ! cs4237b/sound/isa/cs423x/Makefile ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: cs4237b/sound/isa/cs423x/Makefile"
  exit 16
fi

if [ ! cs4237b/sound/isa/wss/wss_lib.c ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: cs4237b/sound/isa/wss/wss_lib.c"
  exit 17
fi

if [ ! cs4237b/sound/isa/wss/Makefile ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: cs4237b/sound/isa/wss/Makefile"
  exit 18
fi

if [ ! cs4237b/include/sound/cs4231-regs.h ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: cs4237b/include/sound/cs4231-regs.h"
  exit 19
fi

if [ ! cs4237b/include/sound/wss.h ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: cs4237b/include/sound/wss.h"
  exit 20
fi

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
KERNEL_ID=$KERNEL_VERSION$LOCALVERSION
RELEASE_VERSION=$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER
RELEASE_DIRECTORY=$HOME_TC/release/$RELEASE_VERSION
HOST_RELEASE_DIRECTORY=./release/$RELEASE_VERSION

CACHE=$HOME_TC/cache/$KERNEL_VERSION
HOST_CACHE=`pwd`/cache/$KERNEL_VERSION
echo "HOST_CACHE=$HOST_CACHE"
mkdir -p $HOST_CACHE

if [ ! -f docker-compose.yml ] || ! grep -q "$KERNEL_URL" docker-compose.yml || ! grep -q "ITERATION_NUMBER=$5" docker-compose.yml || ! grep -q "KERNEL_ID=$KERNEL_ID" docker-compose.yml || ! grep -q "RELEASE_VERISON=$RELEASE_VERSION" docker-compose.yml || ! grep -q "TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION" docker-compose.yml; then
  echo "Did not find $KERNEL_URL or the ITERATION_NUMBER=$ITERATION_NUMBER or the KERNEL_ID=$KERNEL_ID or the TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION in docker-compose.yml. Rewriting docker-compose.yml."
  echo "services:\n"\
    " main:\n"\
    "   build:\n"\
    "     context: .\n"\
    "     args:\n"\
    "       - CORE_GZ=$CORE_GZ\n"\
    "       - CIP_NUMBER=$CIP_NUMBER\n"\
    "       - ITERATION_NUMBER=$ITERATION_NUMBER\n"\
    "       - KERNEL_BRANCH=$KERNEL_BRANCH\n"\
    "       - KERNEL_ID=$KERNEL_ID\n"\
    "       - KERNEL_NAME=$KERNEL_NAME\n"\
    "       - KERNEL_TAR=$KERNEL_TAR\n"\
    "       - KERNEL_URL=$KERNEL_URL\n"\
    "       - KERNEL_VERSION=$KERNEL_VERSION\n"\
    "       - LOCALVERSION=$LOCALVERSION\n"\
    "       - RELEASE_DIRECTORY=$RELEASE_DIRECTORY\n"\
    "       - RELEASE_VERSION=$RELEASE_VERSION\n"\
    "       - TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION\n"\
    "       - TCL_RELEASE_TYPE=$TCL_RELEASE_TYPE\n"\
    "       - TCL_VERSION=$TCL_MAJOR_VERSION_NUMBER.x\n"\
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

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/ipv6-netfilter-$KERNEL_ID.tcz ./
md5sum ./ipv6-netfilter-$KERNEL_ID.tcz > ./ipv6-netfilter-$KERNEL_ID.tcz.md5.txt
cat ./ipv6-netfilter-$KERNEL_ID.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/net-modules-$KERNEL_ID.tcz ./
md5sum ./net-modules-$KERNEL_ID.tcz > ./net-modules-$KERNEL_ID.tcz.md5.txt
cat ./net-modules-$KERNEL_ID.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/parport-modules-$KERNEL_ID.tcz ./
md5sum ./parport-modules-$KERNEL_ID.tcz > ./parport-modules-$KERNEL_ID.tcz.md5.txt
cat ./parport-modules-$KERNEL_ID.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/pcmcia-modules-$KERNEL_ID.tcz ./
md5sum ./pcmcia-modules-$KERNEL_ID.tcz > ./pcmcia-modules-$KERNEL_ID.tcz.md5.txt
cat ./pcmcia-modules-$KERNEL_ID.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/usb-modules-$KERNEL_ID.tcz ./
md5sum ./usb-modules-$KERNEL_ID.tcz > ./usb-modules-$KERNEL_ID.tcz.md5.txt
cat ./usb-modules-$KERNEL_ID.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/wireless-$KERNEL_ID.tcz ./
md5sum ./wireless-$KERNEL_ID.tcz > ./wireless-$KERNEL_ID.tcz.md5.txt
cat ./wireless-$KERNEL_ID.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/bzImage-$RELEASE_VERSION ./
md5sum ./bzImage-$RELEASE_VERSION > ./bzImage-$RELEASE_VERSION.md5.txt
cat ./bzImage-$RELEASE_VERSION.md5.txt

sudo docker cp tcl-core-560z-main-1:$RELEASE_DIRECTORY/core-$RELEASE_VERSION.gz ./
md5sum ./core-$RELEASE_VERSION.gz > ./core-$RELEASE_VERSION.gz.md5.txt
cat ./core-$RELEASE_VERSION.gz.md5.txt

sudo docker cp tcl-core-560z-main-1:$CACHE/* $HOST_CACHE/*

cd ../..
sudo docker compose --progress=plain -f docker-compose.yml down

