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

BUILD_VERSION_ERROR_MESSAGE="Please enter a valid build version as the first parameter. For example 6.12.11.15.9."
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

if [ ! .config ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since .config is "\
    "required."
  exit 7
fi

if [ ! Dockerfile.edit_config ]; then
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

if [ ! -f docker-compose.edit-config.yml ] || ! grep -q "$BUILD_VERSION" docker-compose.edit-config.yml; then
  echo "Did not find $BUILD_VERSION in docker-compose.edit-config.yml. Rewriting docker-compose.edit-config.yml."
  echo "services:\n"\
    " main:\n"\
    "   image: linichotmailca/tcl-core-560z-edit-config:$BUILD_VERSION\n"\
    "   build:\n"\
    "     context: .\n"\
    "     args:\n"\
    "       - KERNEL_BRANCH=v$N1.x\n"\
    "       - KERNEL_VERSION=$KERNEL_VERSION\n"\
    "       - TCL_VERSION=$N4.x\n"\
    "     dockerfile: Dockerfile.edit-config\n" > docker-compose.edit-config.yml
fi

echo "Requirements are met. Building image to edit the linux kernel .config file..."

sudo docker compose --progress=plain -f docker-compose.edit-config.yml build

sudo docker compose --progress=plain -f docker-compose.edit-config.yml up --detach

sudo docker exec -it tcl-core-560z-main-1 make oldconfig

sudo docker exec -it tcl-core-560z-main-1 make menuconfig

HOME_TC=/home/tc
KERNEL_VERSION_NAME=linux-$KERNEL_VERSION
KERNEL_SOURCE_PATH=$HOME_TC/$KERNEL_VERSION_NAME

sudo docker cp tcl-core-560z-main-1:$KERNEL_SOURCE_PATH/.config .

sudo docker compose --progress=plain -f docker-compose.edit-config.yml down

