#!/bin/sh

###################################################################
# Copyright (C) 2026 linic@hotmail.ca Subject to GPL-3.0 license. #
# https://github.com/linic/tcl-core-560z                          #
###################################################################

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

usage()
{
  echo "usage"
  REQUIRED_ARGUMENTS="KERNEL_TRIPLET, (optional) CIP_NUMBER are required."
  CALL_EXAMPLE="./download-kernel.sh 4.4.302 97"
  CALL_EXAMPLE_2="./download-kernel.sh 6.18.8"
  echo "$REQUIRED_ARGUMENTS"
  echo "For example: $CALL_EXAMPLE"
  echo "         or: $CALL_EXAMPLE_2"
  return 2
}

download()
{
  if ! triplet_separator "$1"; then
    return 5
  fi
  KERNEL_VERSION=$MAJOR.$MINOR.$PATCH
  if ! cip_number_check "$2"; then
    return 4
  fi
  resolve_kernel_urls "$2"
  echo "Downloading $KERNEL_URL"
  curl --remote-name "$KERNEL_URL"
  return $?
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
}

main "$@"
