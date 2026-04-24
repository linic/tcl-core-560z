#!/bin/sh

###################################################################
# Copyright (C) 2026 linic@hotmail.ca Subject to GPL-3.0 license. #
# https://github.com/linic/tcl-core-560z                          #
###################################################################

. "$(dirname "$0")/common.sh"

usage()
{
  echo "Please enter the linux kernel version"
  echo "Example: ../tools/generate-patches.sh 6.18.8"
}

normalize_patch_header()
{
  FILE=$1
  ORIG_PATH=$2
  sed -i "1,2s|.*/${ORIG_PATH}\.orig|a/${ORIG_PATH}|g" "$FILE"
  sed -i "1,2s|.*/${ORIG_PATH}|b/${ORIG_PATH}|g"       "$FILE"
  sed -i '1,2s/\([^ ]*\)\t.*/\1/' "$FILE"
}

generate_patches()
{
  if ! get_suffix "$@"; then
    return 1
  fi

  SOURCE="source-$SUFFIX"
  if [ ! -d "$SOURCE" ] && [ -d "source-$1" ]; then
    SOURCE="source-$1"
  fi
  if [ ! -d "$SOURCE" ]; then
    echo "No source dir for $1 (tried source-$SUFFIX and source-$1)"
    return 1
  fi

  PATCH="patches/patches-$SUFFIX"
  mkdir -pv "$PATCH"

  diff -u "$SOURCE/sound/isa/wss/wss_lib.c.orig"       "$SOURCE/sound/isa/wss/wss_lib.c"       > "$PATCH/wss_lib.c.patch"
  diff -u "$SOURCE/sound/isa/cs423x/cs4236_lib.c.orig" "$SOURCE/sound/isa/cs423x/cs4236_lib.c" > "$PATCH/cs4236_lib.c.patch"
  diff -u "$SOURCE/sound/isa/cs423x/cs4236.c.orig"     "$SOURCE/sound/isa/cs423x/cs4236.c"     > "$PATCH/cs4236.c.patch"
  diff -u "$SOURCE/include/sound/wss.h.orig"            "$SOURCE/include/sound/wss.h"           > "$PATCH/wss.h.patch"

  normalize_patch_header "$PATCH/wss_lib.c.patch"    "sound/isa/wss/wss_lib.c"
  normalize_patch_header "$PATCH/cs4236_lib.c.patch" "sound/isa/cs423x/cs4236_lib.c"
  normalize_patch_header "$PATCH/cs4236.c.patch"     "sound/isa/cs423x/cs4236.c"
  normalize_patch_header "$PATCH/wss.h.patch"        "include/sound/wss.h"
}

main()
{
  if [ $# -ne 1 ]; then
    usage
    exit 1
  fi

  case "$1" in
    *.*.*)
      generate_patches "$1"
      ;;
    *)
      usage
      exit 1
      ;;
  esac

  exit "$?"
}

main "$@"
