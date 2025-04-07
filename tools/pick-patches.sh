#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# I originally patched the cs4236 module to work with the cs4237b
# on kernel 6.12.11. I found that patch worked with 6.13.7, but
# not 5.10.235. The code was different enough that I needed new
# patches. I think the 5.10.235 patches can serve to patch v5
# kernel for some time since I plan to stay on 5.10.x and that
# module code shouldn't change much so the next line should
# suffice. I added this to be able to build with v6 kernels which
# use the .config file and with v5 kernels (like 5.10.235) which
# use the .config-v5.x file.
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

if [ ! -d "patches" ] && [ ! -d "patches-5.10.235" ]; then
  echo "Please make sure the directory you're running is the "\
    "extracted linux kernel directory in which cs4237b/patches and "\
    "cs4237b/patches-5.10.235 from https://github.com/linic/tcl-core-560z "\
    "where copied because this script needs to pick which set of patches "\
    "to apply."
  pwd
  ls
  exit 3
fi
if [ $VERSION == "v5.x" ]; then
  rm -rvf patches
  mv -v "patches-5.10.235" patches
elif [ $VERSION == "v6.x" ]; then
  rm -rvf "patches-5.10.235"
fi
exit 0

