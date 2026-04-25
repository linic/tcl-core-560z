#!/bin/sh

###################################################################
# Copyright (C) 2026 linic@hotmail.ca Subject to GPL-3.0 license. #
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# Common functions used by other scripts.
##################################################################

# Validate if the BUILD_VERSION and the CIP contain digits only.
# $1 is the position of the number in the BUILD_VERSION
# $2 is the value of the number in the BUILD_VERISON at that position
# 4.4.302.16.1 has positions 1 2 3 4 5
# For the CIP, for example 97, there's only position 1
check_is_digit() {
  echo "Checking $1 $2"
  non_digits=$(echo "$2" | sed 's/[0-9]//g')
  DIGIT_ERROR_MESSAGE="Digit number $1 is '$2' and is not an integer."
  if [ -n "$non_digits" ]; then
    echo "$DIGIT_ERROR_MESSAGE"
    return 1
  fi
  if [ -z "$2" ]; then
    echo "$DIGIT_ERROR_MESSAGE"
    return 1
  fi
  echo "Number $1 wth value $2 has only digits."
  return 0
}

# Split a version string like 6.18.8 or 4.4.302-cip97 on '.' and '-'
# and validate the first three parts are digits. On success, exports
# MAJOR, MINOR, PATCH as globals (POSIX sh has no 'local', and
# 'set --' inside a function does not propagate to the caller, so
# globals are the cleanest way to return parsed parts).
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
  IFS=$OLD_IFS
  # Check if each part is a valid integer
  n_number=1
  for N in "$1" "$2" "$3"; do
    if ! check_is_digit $n_number $N; then
      return 5
    fi
    n_number=$((n_number+1))
  done
  MAJOR=$1
  MINOR=$2
  PATCH=$3

  return 0
}

# Split a quintuplet like 6.12.65.17.1 on '.' and validate all five
# parts are digits. On success, exports MAJOR MINOR PATCH TCL_MAJOR
# ITERATION as globals. 'KERNEL_VERSION' (the triplet) is also set.
quintuplet_separator()
{
  VERSION_QUINTUPLET=$1
  OLD_IFS=$IFS
  IFS="."
  set -- $VERSION_QUINTUPLET
  IFS=$OLD_IFS
  n_number=1
  for N in "$1" "$2" "$3" "$4" "$5"; do
    if ! check_is_digit $n_number $N; then
      return 5
    fi
    n_number=$((n_number+1))
  done
  MAJOR=$1
  MINOR=$2
  PATCH=$3
  TCL_MAJOR=$4
  ITERATION=$5
  KERNEL_VERSION=$MAJOR.$MINOR.$PATCH

  return 0
}

# Validate a CIP number (digits only). No-op (returns 0) if empty.
cip_number_check()
{
  if [ -z "$1" ]; then
    return 0
  fi
  if ! check_is_digit 1 "$1"; then
    echo "CIP_NUMBER is wrong: $1. For example, enter 97 if your tar name has something like 4.4.302-cip97."
    return 4
  fi
  return 0
}

# Given MAJOR.MINOR.PATCH (already in KERNEL_VERSION) and an optional
# CIP number as $1, export KERNEL_BRANCH KERNEL_NAME KERNEL_TAR
# KERNEL_URL. When a CIP number is given, KERNEL_VERSION is rewritten
# to include '-cipN' and the CIP kernel.org snapshot URL is used.
resolve_kernel_urls()
{
  CIP_NUMBER=$1
  KERNEL_BRANCH=v$MAJOR.x
  KERNEL_NAME=linux-$KERNEL_VERSION
  KERNEL_TAR=$KERNEL_NAME.tar.xz
  KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/$KERNEL_BRANCH/$KERNEL_TAR
  if [ -n "$CIP_NUMBER" ]; then
    KERNEL_VERSION=$KERNEL_VERSION-cip$CIP_NUMBER
    KERNEL_NAME=linux-cip-$KERNEL_VERSION
    KERNEL_TAR=$KERNEL_NAME.tar.gz
    KERNEL_URL=https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git/snapshot/$KERNEL_TAR
    echo "$KERNEL_VERSION is maintained by CIP."
  fi
  return 0
}

# .config- and patches- have suffixes. Reads MAJOR and MINOR that
# triplet_separator exported, then picks the suffix:
#   4|5          -> MAJOR
#   6 MINOR<18   -> MAJOR
#   6 MINOR>=18  -> MAJOR.MINOR
# Exports SUFFIX.
get_suffix()
{
  if ! triplet_separator "$@"; then
    return 5
  fi
  SUFFIX=""
  case "$MAJOR" in
    4|5)
      SUFFIX="$MAJOR"
      ;;
    6)
      if [ "$MINOR" -lt 18 ]; then
        SUFFIX="$MAJOR"
      else
        SUFFIX="$MAJOR.$MINOR"
      fi
      ;;
  esac

  if [ -z "$SUFFIX" ]; then
    echo "No suffix for $KERNEL_VERSION"
    return 1
  fi

  echo "Using $SUFFIX"

  return 0
}
