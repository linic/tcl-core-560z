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

if [ ! .config ]; then
  echo "Please make sure this folder is the base folder of "\
    "https://github.com/linic/tcl-core-560z since .config is "\
    "required."
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

if [ ! -f docker-compose.yml ] || ! grep -q "$BUILD_VERSION" docker-compose.yml; then
  echo "Did not find $BUILD_VERSION in docker-compose.yml. Rewriting docker-compose.yml."
  echo "services:\n"\
    " main:\n"\
    "   image: linichotmailca/tcl-core-560z:$BUILD_VERSION\n"\
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
    "     dockerfile: Dockerfile\n" > docker-compose.yml
fi

echo "Requirements are met. Building and getting..."
echo "  alsa-modules-$KERNEL_VERSION.tcz"
echo "  net-modules-$KERNEL_VERSION.tcz"
echo "  parport-modules-$KERNEL_VERSION.tcz"
echo "  pcmcia-modules-$KERNEL_VERSION.tcz"
echo "  usb-modules-$KERNEL_VERSION.tcz"
echo "  bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION"
echo "  core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz"

sudo docker compose --progress=plain -f docker-compose.yml build

sudo docker compose --progress=plain -f docker-compose.yml up --detach

mkdir -p ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/

sudo docker cp tcl-core-560z-main-1:/home/tc/alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/
md5sum ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz > ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
cat ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/alsa-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:/home/tc/net-modules-$KERNEL_VERSION-tinycore-560z.tcz ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/
md5sum ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/net-modules-$KERNEL_VERSION-tinycore-560z.tcz > ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/net-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
cat ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/net-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:/home/tc/parport-modules-$KERNEL_VERSION-tinycore-560z.tcz ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/
md5sum ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/parport-modules-$KERNEL_VERSION-tinycore-560z.tcz > ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/parport-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
cat ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/parport-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:/home/tc/pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/
md5sum ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz > ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
cat ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/pcmcia-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:/home/tc/usb-modules-$KERNEL_VERSION-tinycore-560z.tcz ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/
md5sum ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/usb-modules-$KERNEL_VERSION-tinycore-560z.tcz > ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/usb-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt
cat ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/usb-modules-$KERNEL_VERSION-tinycore-560z.tcz.md5.txt

sudo docker cp tcl-core-560z-main-1:/home/tc/bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/
md5sum ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION > ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION.md5.txt
cat ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/bzImage-$KERNEL_VERSION.$TINYCORE_ITERATION.md5.txt

sudo docker cp tcl-core-560z-main-1:/home/tc/core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/
md5sum ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz > ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz.md5.txt
cat ./release/$KERNEL_VERSION.$TINYCORE_ITERATION/core-$KERNEL_VERSION.$TINYCORE_ITERATION.gz.md5.txt

sudo docker compose --progress=plain -f docker-compose.yml down

