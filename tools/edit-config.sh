#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# The script checks all dependencies are available.
# It builds the docker image to edit the linux kernel .config
# file, starts a container, attaches to it, runs make oldconfig,
# copies the resulting .config back in the repo and puts the 
# container down.
##################################################################

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

HOME_TC=/home/tc

ARGUMENT_ERROR_MESSAGE="Please enter a valid release version, TCL_DOCKER_IMAGE_VERSION and optionally a CIP number: 4.4.302.7.1 16.x 97"
if [ ! $# -ge 2 ]; then
  echo $ARGUMENT_ERROR_MESSAGE
  exit 1
fi
# Save the first parameter as the build version.
COMMON_VERSION_NUMBERS=$1
TCL_DOCKER_IMAGE_VERSION=$2
CIP_NUMBER=$3
if [ ! -z $CIP_NUMBER ]; then
  if ! check_is_digit 1 $CIP_NUMBER; then
    echo "CIP_NUMBER is wrong: $CIP_NUMBER. For example, enter 97 if your tar name has something like 4.4.302-cip97."
    exit 4
  fi
fi
# IFS is by default space, tab and newline. When 6.12.11.15.9 is entered, it is 1 parameter and in the first positional parameter.
# Set the Internal Field Separator to "." that way each digit of 6.12.11.15.9 will be separated in different variables.
OLD_IFS=$IFS
IFS=". "
# Use set to reset the positional parameters.
set -- $COMMON_VERSION_NUMBERS
# Check N1 to N5 are integers.
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
    "https://github.com/linic/tcl-core-560z since .config is "\
    "and .config-v5.x are required."
  exit 9
fi

if [ ! Dockerfile.edit_config ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since Dockerfile is "\
    "required."
  exit 10
fi

if [ ! "tools/pick-config.sh" ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since "\
    "tools/pick-config.sh is required."
  exit 11
fi

if [ ! echo_sleep ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: echo_sleep"
  exit 12
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
KERNEL_ID=$KERNEL_VERSION$LOCAL_VERSION
RELEASE_VERSION=$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER

if [ ! -f docker-compose.edit-config.yml ] || ! grep -q "$KERNEL_TAR_URL" docker-compose.edit-config.yml|| ! grep -q "RELEASE_VERSION=$RELEASE_VERSION" docker-compose.edit-config.yml || ! grep -q "TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION" docker-compose.yml; then
  echo "Did not find $KERNEL_TAR_URL or KERNEL_VERSION=$KERNEL_VERSION or the TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION in docker-compose.edit-config.yml. Rewriting docker-compose.edit-config.yml."
  echo "services:\n"\
    " main:\n"\
    "   image: linichotmailca/tcl-core-560z-edit-config:$COMMON_VERSION_NUMBERS\n"\
    "   build:\n"\
    "     context: .\n"\
    "     args:\n"\
    "       - KERNEL_BRANCH=$KERNEL_BRANCH\n"\
    "       - KERNEL_ID=$KERNEL_ID\n"\
    "       - KERNEL_NAME=$KERNEL_NAME\n"\
    "       - KERNEL_TAR=$KERNEL_TAR\n"\
    "       - KERNEL_URL=$KERNEL_URL\n"\
    "       - KERNEL_VERSION=$KERNEL_VERSION\n"\
    "       - RELEASE_VERSION=$RELEASE_VERSION\n"\
    "       - TCL_DOCKER_IMAGE_VERSION=$TCL_DOCKER_IMAGE_VERSION\n"\
    "       - TCL_VERSION=$TCL_MAJOR_VERSION_NUMBER.x\n"\
    "     dockerfile: Dockerfile.edit-config\n" > docker-compose.edit-config.yml
fi

echo "Requirements are met. Building image to edit the linux kernel .config file..."

if ! sudo docker compose --progress=plain -f docker-compose.edit-config.yml build; then
  echo "Docker build to edit the .config failed!"
  exit 20
fi

sudo docker compose --progress=plain -f docker-compose.edit-config.yml up --detach

sudo docker exec -it tcl-core-560z-main-1 make oldconfig

# ncursesw.tcz and other ncursesw-*.tcz are installed, but 4.4.302-cip97 complains it can't find:
# scripts/kconfig/conf  --oldconfig Kconfig
#
# configuration written to .config
#
#  HOSTCC  scripts/kconfig/mconf.o
# *** Unable to find the ncurses libraries or the
# *** required header files.
# *** 'make menuconfig' requires the ncurses libraries.
# *** 
# *** Install ncurses (ncurses-devel) and try again.
# *** 
# make[1]: *** [scripts/kconfig/Makefile:199: scripts/kconfig/dochecklxdialog] Error 1
# I don't have a solution for this yet so I edit the config file on another machine
# where it works.
if [ ! $1 = 4 ]; then
  sudo docker exec -it tcl-core-560z-main-1 make menuconfig
fi

HOME_TC=/home/tc
KERNEL_SOURCE_PATH=$HOME_TC/$KERNEL_NAME

if [ $1 = "4" ]; then
  sudo docker cp tcl-core-560z-main-1:$KERNEL_SOURCE_PATH/.config ./.config-v4.x
elif [ $1 = "5" ]; then
  sudo docker cp tcl-core-560z-main-1:$KERNEL_SOURCE_PATH/.config ./.config-v5.x
else
  sudo docker cp tcl-core-560z-main-1:$KERNEL_SOURCE_PATH/.config .
fi

sudo docker compose --progress=plain -f docker-compose.edit-config.yml down

