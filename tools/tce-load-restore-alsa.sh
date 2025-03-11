#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

##################################################################
#`/home/tc/configuration/asound.state` won't exist the first time.
# You'll have to run manually:
# ```
# tce-load -i alsa-config
# tce-load -i alsa
# alsamixer
# ```
# and set the master volume and the pcm volume to 100. Then,
# ```
# sudo alsactl store CS4237B
# sudo cp /usr/local/etc/alsa/asound.state /home/tc/configuration/
# ```
# You should then be able to `mpg123 your.mp3` to play a file.
# Still no sound? Try `sudo alsactl init CS4237B`. I sometimes
# have to do that maybe because some registers of the CS4237B are
# set to the go to the wrong values...? Also unmute the sound
# using the Fn and volume keys of your keyboard. Make sure you
# hear the "beep" the volume up keybaoard key produces.
##################################################################

# Required for alsamixer to work.
tce-load -i alsa-config
# alsa depends on alsa-modules-KERNEL.tcz and will load them
tce-load -i alsa
tce-load -i mpg123
sudo cp /home/tc/configuration/asound.state /usr/local/etc/alsa/
sudo alsactl restore CS4237B

