#!/bin/sh

###################################################################
# Copyright (C) 2026 linic@hotmail.ca Subject to GPL-3.0 license. #
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
# use the patches file and with v5 kernels (like 5.10.235) which
# use the patches-v5.x file.
# Since I planned to stay on the 5.10.x for a long time, I need
# compatibility with the CIP maintained kernels .tar.gz. The
# 4.4.302-cip97 is the newest oldest supported kernel. 4.4 will
# be supported until January 2027 according to
# https://wiki.linuxfoundation.org/civilinfrastructureplatform/start
##################################################################

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

usage()
{
  echo "Please enter the linux kernel version"
  echo "Example ./pick-patches.sh 6.18.8"
}

pick_patches()
{
  KERNEL_VERSION="$1"
  triplet_separator "$@"
  echo "Picking patches $1 $2 $3 $4"

  PATCH_DIR=""
  if [ patches-$KERNEL_VERSION ]; then
    PATCH_DIR="patches-$KERNEL_VERSION"
  elif [ patches-$1.$2 ]; then
    PATCH_DIR="patches-$1.$2"
  elif [ patches-$1 ]; then
    PATCH_DIR="patches-$1"
  fi

  if [ -z "$PATCH_DIR" ]; then
    echo "Could not find patches for $KERNEL_VERSION"
    return 1
  fi

  mv -v "$PATCH_DIR" "patches"
  rm -rvf "patches-*"

  return 0
}

main()
{
  if [ ! $# -eq 1 ]; then
    usage "$@"
    exit "$?"
  fi

  case "$1" in
    *.*.*)
      pick_patches "$1"
      ;;
    *)
      usage "$@"
      ;;
  esac

  exit "$?"
}

main "$@"
