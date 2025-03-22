#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# The script checks all dependencies are available.
# It builds a docker image to trim core.gz.
##################################################################

BUILD_VERSION_ERROR_MESSAGE="Please enter a build version, TCL_RELEASE_TYPE and core.gz or rootfs.gz. For example: build-all.sh 6.12.11.15.9 release core.gz"
if [ ! $# -eq 3 ]; then
  echo $BUILD_VERSION_ERROR_MESSAGE
  exit 6
fi
# Save the first parameter as the build version.
BUILD_VERSION=$1
TCL_RELEASE_TYPE=$2
if [ $TCL_RELEASE_TYPE != "release" && $TCL_RELEASE_TYPE!= "release_candidates" ]; then
  echo "The 2nd parameter should be either 'release' or 'release_candidates'."
  exit 12
fi
CORE_GZ=$3
if [ $CORE_GZ != "core.gz" && $CORE_GZ != "rootfs.gz" ]; then
  echo "The 3rd parameter should be either 'core.gz' or 'rootfs.gz'."
  exit 13
fi
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

if [ ! Dockerfile.trim ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since Dockerfile.trim is "\
    "required."
  exit 8
fi

if [ ! echo_sleep ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since required "\
    "file is missing: echo_sleep"
  exit 10
fi

if [ ! -f docker-compose.trim.yml ] || ! grep -q "$BUILD_VERSION" docker-compose.trim.yml; then
  echo "Did not find $BUILD_VERSION in docker-compose.trim.yml. Rewriting docker-compose.trim.yml."
  echo "services:\n"\
    " trim:\n"\
    "   build:\n"\
    "     context: .\n"\
    "     args:\n"\
    "       - CORE_GZ=$CORE_GZ\n"\
    "       - ITERATION_NUMBER=$N5\n"\
    "       - KERNEL_BRANCH=v$N1.x\n"\
    "       - KERNEL_SUFFIX=tinycore-560z\n"\
    "       - KERNEL_VERSION=$KERNEL_VERSION\n"\
    "       - TCL_MAJOR_VERSION_NUMBER=$N4\n"\
    "       - TCL_RELEASE_TYPE=$TCL_RELEASE_TYPE\n"\
    "       - TCL_VERSION=$N4.x\n"\
    "     tags:\n"\
    "       - linichotmailca/tcl-core-560z-trim:$BUILD_VERSION\n"\
    "       - linichotmailca/tcl-core-560z-trim:latest\n"\
    "     dockerfile: Dockerfile.trim\n" > docker-compose.trim.yml
fi

echo "Requirements are met. Building image to trim the official core.gz..."

sudo docker compose --progress=plain -f docker-compose.trim.yml build

sudo docker compose --progress=plain -f docker-compose.trim.yml up --detach

sudo docker exec -it tcl-core-560z-trim-1 sh
HOME_TC=/home/tc
KERNEL_VERSION_NAME=linux-$KERNEL_VERSION
KERNEL_SOURCE_PATH=$HOME_TC/$KERNEL_VERSION_NAME
mkdir -p ./release/$BUILD_VERSION-trim/
sudo docker cp tcl-core-560z-trim-1:$HOME_TC/core-$BUILD_VERSION-trim.gz ./release/$BUILD_VERSION-trim/
cd ./release/$BUILD_VERSION-trim/
md5sum core-$BUILD_VERSION-trim.gz > core-$BUILD_VERSION-trim.gz.md5.txt
cd ../..
sudo docker compose --progress=plain -f docker-compose.trim.yml down

