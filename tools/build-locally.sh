#!/bin/sh

###################################################################
# Copyright (C) 2026 linic@hotmail.ca Subject to GPL-3.0 license. #
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
# Build natively on a booted Tiny Core Linux (no Docker). Produces
# the same artifacts as the Docker build (bzImage, modules .tczs,
# core-<version>.gz + md5s) in $HOME_TC/release/$RELEASE_VERSION/.
#
# Call this from a fresh checkout of the repo while booted on the
# target (e.g. the 560Z). The first run will stage the repo files
# into /home/tc/kernel_configs, /home/tc/cs4237b, /home/tc/tools
# and /home/tc/cache, then invoke make-bzImage-modules-tczs.sh.
#
# Modelled on rust-i586/tools/build-locally.sh.
##################################################################

# Source (include) functions from tools/common.sh
. "$(dirname "$0")/common.sh"

HOME_TC=/home/tc
TOOLS=$HOME_TC/tools
KERNEL_CONFIGS=$HOME_TC/kernel_configs
CS4237B_PATCHES=$HOME_TC/cs4237b
CACHE=$HOME_TC/cache

usage()
{
  echo "usage"
  REQUIRED_ARGUMENTS="VERSION_QUINTUPLET, TCL_RELEASE_TYPE, CORE_GZ (core.gz|rootfs.gz), LOCAL_VERSION, (optional) CIP_NUMBER are required."
  CALL_EXAMPLE="./build-locally.sh 4.4.302.16.1 release rootfs.gz -tinycore-560z 97"
  CALL_EXAMPLE_2="./build-locally.sh 6.18.8.17.1 release rootfs.gz -tinycore-560z"
  echo "$REQUIRED_ARGUMENTS"
  echo "For example: $CALL_EXAMPLE"
  echo "         or: $CALL_EXAMPLE_2"
  echo "Note: consider running this in tmux so you can detach long builds."
  return 2
}

# Copy the repo's build inputs into the paths make-bzImage-modules-tczs.sh
# expects (same layout the Dockerfile sets up). If REPO_DIR is the same
# as HOME_TC (already staged), this is a no-op.
stage_inputs()
{
  if [ "$REPO_DIR" = "$HOME_TC" ]; then
    echo "Already running from $HOME_TC; skipping stage."
    return 0
  fi
  echo "Staging inputs from $REPO_DIR into $HOME_TC."

  mkdir -pv "$TOOLS"
  cp -v "$REPO_DIR/tools/"* "$TOOLS/"
  chmod +x "$TOOLS/"*.sh

  mkdir -pv "$KERNEL_CONFIGS"
  cp -v "$REPO_DIR"/.config-* "$KERNEL_CONFIGS/"

  mkdir -pv "$CS4237B_PATCHES/sound-isa-cs4237b" "$CS4237B_PATCHES/integration"
  cp -rv "$REPO_DIR/cs4237b/src/sound/isa/cs4237b/." "$CS4237B_PATCHES/sound-isa-cs4237b/"
  cp -rv "$REPO_DIR/cs4237b/src/integration-patches/." "$CS4237B_PATCHES/integration/"

  mkdir -pv "$CACHE"
  if [ -d "$REPO_DIR/cache/$KERNEL_VERSION" ]; then
    cp -rv "$REPO_DIR/cache/$KERNEL_VERSION" "$CACHE/"
  fi
  if [ -d "$REPO_DIR/cache/rootfs" ]; then
    cp -rv "$REPO_DIR/cache/rootfs" "$CACHE/"
  fi

  return 0
}

build()
{
  # package-core-gz.sh reads TCL_VERSION and TCL_RELEASE_TYPE from
  # the environment (in the Docker path they come from ARGs).
  export TCL_VERSION="$TCL_MAJOR.x"
  export TCL_RELEASE_TYPE

  "$TOOLS/tce-load-requirements.sh"
  cd "$HOME_TC"
  "$TOOLS/make-bzImage-modules-tczs.sh" "$VERSION_QUINTUPLET" "$LOCAL_VERSION" "$CORE_GZ" "$CIP_NUMBER"
  return $?
}

main()
{
  if [ $# -lt 4 ]; then
    usage "$@"
    exit "$?"
  fi

  VERSION_QUINTUPLET=$1
  TCL_RELEASE_TYPE=$2
  CORE_GZ=$3
  LOCAL_VERSION=$4
  CIP_NUMBER=$5

  if [ "$TCL_RELEASE_TYPE" != "release" ] && [ "$TCL_RELEASE_TYPE" != "release_candidates" ]; then
    echo "The 2nd parameter should be either 'release' or 'release_candidates'."
    exit 2
  fi
  if [ "$CORE_GZ" != "core.gz" ] && [ "$CORE_GZ" != "rootfs.gz" ]; then
    echo "The 3rd parameter should be either 'core.gz' or 'rootfs.gz'."
    exit 3
  fi
  if ! quintuplet_separator "$VERSION_QUINTUPLET"; then
    usage "$@"
    exit 5
  fi
  if ! cip_number_check "$CIP_NUMBER"; then
    exit 4
  fi
  resolve_kernel_urls "$CIP_NUMBER"

  # Determine the repo dir: the parent of the tools/ dir this script
  # lives in. If we were launched via $HOME_TC/tools, the "repo" is
  # effectively $HOME_TC (already-staged case).
  TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
  REPO_DIR=$(dirname "$TOOLS_DIR")
  echo "REPO_DIR=$REPO_DIR  HOME_TC=$HOME_TC"

  stage_inputs
  build
  exit "$?"
}

main "$@"
