#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

# alsa-config is required for alsamixer to work or there's an error popping out on my 560z.
tce-load -w alsa-config
tce-load -w alsa
# mpg123 plays mp3 files
tce-load -w mpg123

