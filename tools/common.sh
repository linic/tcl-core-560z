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

triplet_separator()
{
  OLD_PARAMS=("$@")
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
      echo "Restoring old params because of error in digit check."
      set -- "${old_params[@]}"
      return 5
    fi
    n_number=$((n_number+1))
  done
  # Restore IFS otherwise all commands below will split parameters using dots and will fail.
  IFS=$OLD_IFS

  return 0 
}

