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

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

usage()
{
ERROR_MESSAGE="Please enter the linux kernel version"
if [ ! $# -eq 1 ]; then
  echo $ERROR_MESSAGE
  return 2
fi
}

triplet_separator()
{
  KERNEL_VERSION=$1
  # IFS is by default space, tab and newline. When 6.18.8 is entered, it is 1 parameter and in the first positional parameter.
  # Set the Internal Field Separator to "." that way each digit of 6.18.8 will be separated in different variables.
  OLD_IFS=$IFS
  # Set also to - as a separator to handle 4.4.302-cip97
  IFS=".-"
  # Use set to reset the positional parameters.
  set -- $KERNEL_VERSION
  # Check if each part is a valid integer
  n_number=1
  for N in "$1" "$2" "$3"; do
    if ! check_is_digit $n_number $N; then
      echo "$ARGUMENT_ERROR_MESSAGE"
      return 5
    fi
    n_number=$((n_number+1))
  done
  # Restore IFS otherwise all commands below will split parameters using dots and will fail.
  IFS=$OLD_IFS

  pick_patches "$1" "$2" "$3" "$4"
}

pick_patches()
{
  echo "Picking patches $1 $2 $3 $4"

  if [ -d "patches-4.4.302-cip97" ] && [ -d "patches" ] && [ -d "patches-5.10.235" ] && [ -d "patches-6.18.8" ]; then
    echo "Found all patches. Continuing..."
  else
    echo "Please make sure the directory you're running is the "\
      "extracted linux kernel directory in which cs4237b/patches, "\
      "cs4237b/patches-5.10.235 and cs4237b/patches-4.4.302-cip97 "\
      "from https://github.com/linic/tcl-core-560z "\
      "where copied because this script needs to pick which set of patches "\
      "to apply."
    pwd
    ls
    return 3
  fi
  if [ $1 == 4 ]; then
    mv -v "patches-4.4.302-cip97" "patches"
    rm -rvf "patches-5.10.235"
    rm -rvf "patches-6"
    rm -rvf "patches-6.18.8"
  elif [ $1 == 5 ]; then
    rm -rvf "patches-4.4.302-cip97"
    mv -v "patches-5.10.235" "patches"
    rm -rvf "patches-6"
    rm -rvf "patches-6.18.8"
  elif [ $1 == 6 ]; then
    if [ $2 < 18]; then
      rm -rvf "patches-4.4.302-cip97"
      rm -rvf "patches-5.10.235"
      mv -v "patches-6" "patches"
      rm -rvf "patches-6.18.8"
    else
      rm -rvf "patches-4.4.302-cip97"
      rm -rvf "patches-5.10.235"
      rm -rvf "patches-6"
      mv -v "patches-6.18.8" "patches"
    fi
  fi

  return 0
}

main()
{
  if [ $# -lt 1 ]; then
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
