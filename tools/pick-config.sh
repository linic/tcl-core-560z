#!/bin/sh

###################################################################
# Copyright (C) 2026 linic@hotmail.ca Subject to GPL-3.0 license. #
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# I added this to be able to build with v6 kernels which use the
# .config file and with v5 kernels
# (like 5.10.235) which use the .config-v5.x file.
##################################################################

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

usage()
{
  echo "Please enter the linux kernel version"
  echo "Example ./pick-config.sh 6.18.8"
}

pick_config()
{
  KERNEL_VERSION="$1"
  get_suffix "$@"
  echo "Picking config $SUFFIX"

  CONFIG_FILE=".config-$SUFFIX"
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "$CONFIG_FILE does not exist for $KERNEL_VERSION"
    return 1
  fi

  mv -v "$CONFIG_FILE" ".config"
  rm -rvf ".config-*"

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
      pick_config "$1"
      ;;
    *)
      usage "$@"
      ;;
  esac

  exit "$?"
}

main "$@"
