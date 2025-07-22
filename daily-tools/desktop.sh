#!/bin/sh

###################################################################
# Based on the guidance from Rich
# https://forum.tinycorelinux.net/index.php/topic,27458.msg176935.html#msg176935
###################################################################

###################################################################
# I'm using a REALTEK 8152 USB to Ethernet adapter so usb modules
# need to be loaded first to detect the adapter.
# tce-load will automatically resolve KERNEL to the running kernel
# for example 6.13.7-tinycore-560z
###################################################################

PROGRAM_NAME=${0##*/}
VERSION=1
AUTHOR="linic@hotmail.ca"

# Load what I call the "full experience" as suggested by Rich.
# A terminal is available in the desktop enviroment and there's an icon
# bar with apps at the bottom of the desktop.
full()
{
  tce-load -w Xvesa flwm_topside aterm wbar
  tce-load -i Xvesa flwm_topside aterm wbar
}

# Load the minimal experience without the abar and no terminal within the desktop.
# CTRL + ALT + F1: goes back to the shell/terminal from which startx was called.
# CTRL + ALT + F2: goes back to the desktop.
minimum()
{
  tce-load -w Xvesa flwm_topside
  tce-load -i Xvesa flwm_topside
}


usage()
{
  if [ $# -eq 0 ]; then
    echo "usage: $PROGRAM_NAME [ full | minimum ] # @version $VERSION (c) $AUTHOR"
    exit 0
  else
    echo "$@"
    exit 0
  fi
}

main()
{
  [ $# -lt 1 ] && usage
  "$@"
  startx
}

main "$@"

