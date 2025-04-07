#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# I added this to be able to build with v6 kernels which use the
# .config file and with v5 kernels
# (like 5.10.235) which use the .config-v5.x file.
##################################################################

ERROR_MESSAGE="Please enter the linux kernel branch (v5.x or v6.)"
if [ ! $# -eq 1 ]; then
  echo $ERROR_MESSAGE
  exit 1
fi

VERSION=$1
if [ $VERSION != "v5.x" ] && [ $VERSION != "v6.x" ]; then
  echo "Only v5.x or v6.x are supported for now."
  exit 2
fi
if [ ! .config-v5 ] && [ ! .config ]; then
  echo "Please make sure the directory you're running is the "\
    "extracted linux kernel directory in which cs4237b/patches and "\
    "cs4237b/patches-5.10.235 from https://github.com/linic/tcl-core-560z "\
    "where copied because this script needs to pick which set of patches "\
    "to apply."
  exit 3
fi
if [ $VERSION == "v5.x" ]; then
  rm -v .config
  mv -v .config-v5.x .config
elif [ $VERSION == "v6.x" ]; then
  rm -v .config-v5.x
fi
exit 0

