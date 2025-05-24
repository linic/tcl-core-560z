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
# Since I planned to stay on the 5.10.x for a long time, I need
# compatibility with the CIP maintained kernels .tar.gz. The
# 4.4.302-cip97 is the newest oldest supported kernel. 4.4 will
# be supported until January 2027 according to
# https://wiki.linuxfoundation.org/civilinfrastructureplatform/start
##################################################################

ERROR_MESSAGE="Please enter the linux kernel branch (v4.x, v5.x or v6.)"
if [ ! $# -eq 1 ]; then
  echo $ERROR_MESSAGE
  exit 1
fi

VERSION=$1
if [ $VERSION != "v4.x" ] && [ $VERSION != "v5.x" ] && [ $VERSION != "v6.x" ]; then
  echo "Only v4.x, v5.x or v6.x are supported for now."
  exit 2
fi

if [ ! -d "patches-4.4.302-cip97" ] && [ ! -d "patches" ] && [ ! -d "patches-5.10.235" ]; then
  echo "Please make sure the directory you're running is the "\
    "extracted linux kernel directory in which cs4237b/patches, "\
    "cs4237b/patches-5.10.235 and cs4237b/patches-4.4.302-cip97 "\
    "from https://github.com/linic/tcl-core-560z "\
    "where copied because this script needs to pick which set of patches "\
    "to apply."
  pwd
  ls
  exit 3
fi
if [ $VERSION == "v4.x" ]; then
  rm -rvf patches
  rm -rvf "patches-5.10.235"
  mv -v "patches-4.4.302-cip97" patches
elif [ $VERSION == "v5.x" ]; then
  rm -rvf patches
  rm -rvf "patches-4.4.302-cip97"
  mv -v "patches-5.10.235" patches
elif [ $VERSION == "v6.x" ]; then
  rm -rvf "patches-5.10.235"
  rm -rvf "patches-4.4.302-cip97"
fi
exit 0

