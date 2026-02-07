#!/bin/sh

###################################################################
# Copyright (C) 2026  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

usage()
{
  echo "usage"
  REQUIRED_ARGUMENTS="Common version numbers, (optional) CIP number are required."
  CALL_EXAMPLE="./download-kernel.sh 4.4.302 97"
  CALL_EXAMPLE_2="./download-kernel.sh 6.18.8"
  echo "$REQUIRED_ARGUMENTS"
  echo "For example: $CALL_EXAMPLE"
  echo "         or: $CALL_EXAMPLE_2"
  return 2
}

download()
{
  echo "downloading $1 $2"
  . "$(dirname "$0")/common.sh"
  COMMON_VERSION_NUMBERS=$1

  if [ $# -ge 2 ]; then
    CIP_NUMBER=$2
    if [ ! -z CIP_NUMBER ]; then
      if ! check_is_digit 1 $CIP_NUMBER; then
        echo "CIP_NUMBER is wrong: $CIP_NUMBER. For example, enter 97 for 4.4.302-cip97."
        return 4
      fi
    fi
  fi

  # IFS is by default space, tab and newline. When 6.18.8 is entered, it is 1 parameter and in the first positional parameter.
  # Set the Internal Field Separator to "." that way each digit of 6.18.8 will be separated in different variables.
  OLD_IFS=$IFS
  IFS="."
  # Use set to reset the positional parameters.
  set -- $COMMON_VERSION_NUMBERS
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
  KERNEL_VERSION=$1.$2.$3
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
  curl --remote-name $KERNEL_URL
}

main()
{
  if [ $# -lt 1 ]; then
    usage "$@"
    exit "$?"
  fi

  case "$1" in
    *.*.*)
      download "$@"
      exit "$?"
      ;;
    *)
      usage "$@"
      exit "$?"
      ;;
  esac
  exit 10
}

main "$@"
