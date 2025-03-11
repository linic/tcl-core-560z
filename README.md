# tcl-core-560z

## Before continuing
There's a simpler and faster method for customizing 
[the official `core.gz` here](https://forum.tinycorelinux.net/index.php/topic,27458.msg176935.html#msg176935)
to get a smaller `core.gz` which should start correctly when RAM is a bottleneck.
This will get you a version of tinycore linux which will work with the official
`NAME-modules-KERNEL.tcz` files like `alsa-modules-KERNEL.tcz`.

If you build your own kernel with the method described below, starting with kernel 6.12.11, some
`NAME-modules-KERNEL.tcz` files are generated.

If you are on a quest to get sound working on the 560z, I modified the cs4236 driver and put the result in the
[6.12.11](./6.12.11/) folder. This gets bundled in the `alsa-modules-6.12.11-tinycore-560z.tcz`. Tinycore 14.0 and
my custom builds before 6.12.11.15.8 would give me `cs4236+ chip detected, but control port 0xffffffff is not valid`.
It looks like a working version of a driver for the CS4237B specifically on the 560z hasn't existed for a
long time. All the workarounds I found on the net didn't work for me. More details in another section below.

### Which `NAME-modules-KERNEL.tcz` files are generated?
#### Replacement for `alsa-modules-KERNEL.tcz` referred to by [`alsa.tcz.dep`](http://tinycorelinux.net/15.x/x86/tcz/alsa.tcz.dep)
alsa-modules-6.12.11-tinycore-560z.tcz
#### Additional custom `NAME-modules-KERNEL.tcz`
net-modules-6.12.11-tinycore-560z.tcz
parport-modules-6.12.11-tinycore-560z.tcz
pcmcia-modules-6.12.11-tinycore-560z.tcz
usb-modules-6.12.11-tinycore-560z.tcz
#### No replacement for
original-modules-KERNEL.tcz

## Summary
I originally based my custom kernel on the `.config` of
[TCL 12.0](http://tinycorelinux.net/12.x/x86/release/src/kernel/config-5.10.3-tinycore).
I'm now at 6.12.11. I used `make oldconfig` to move from 5.10.3 to 5.10.232. Then, I moved to 6.12.11 eventually.
I also used `make menuconfig` to unselect many features and change the processor configuration to Pentium II.

## Why?
My Thinkpad 560z 64 MB of RAM. As far as my experience goes, TCL Core 14.0 is the last version of TCL which can be
supported without trimming `core.gz` or customizing the kernel and modules because the amount of RAM is too small
and `init` won't start. By selecting only the kernel (and modules) features needed and repacking `core.gz`,
it's possible to get a much smaller kernel and boot-up TCL core 15.0 and possibly many other TCL versions
which will come after.

### Why the official TCL Core 15.0 won't start?
Even with a swap partition, TCL Core 15.0 tries to start `init` before loading the swap and since there is 
not enough memory without the swap, `init` fails with codes such as 
[init (error -26) with Core 15.0](https://forum.tinycorelinux.net/index.php/topic,27458.0.html) (and I also
got error -2 while testing various custom kernels and modules.

## How to build?
To build the custom linux kernel and `core.gz`: 
`sudo docker compose --progress=plain -f docker-compose.yml build`

To copy them out of a running container: 
`sudo docker compose -f docker-compose.yml up` and in another terminal 
run the [build-all.sh](./tools/build-all.sh) script.

## How to use the custom files on the 560z?
Get those files on the 560z in your preferred way. The scripts in [tools](./tools) could be useful.
You could use [ftp-get-kernel.sh](./tools/ftp-get-kernel.sh) if you put all the files on an FTP server.
[ftp-get-kernel.sh](./tools/ftp-get-kernel.sh) depends on [ftp-get.sh](./tools/ftp-get.sh)
which uses `ftpget` included in the `busybox` which is a core part of tinycore.
[ftp-get-kernel.sh](./tools/ftp-get-kernel.sh) will edit `tce/boot/extlinux/extlinux.conf`
and add a new entry in the boot menu. Reboot and try to boot from the new entry.

## edit-config
The [Dockerfile.edit-config](Dockerfile.edit-config) and
[docker-compose.edit-config.yml](docker-compose.edit-config.yml)
can help edit the [.config](.config) file which are used to build the custom kernel.

Build with: `sudo docker compose --progress=plain -f docker-compose.yml build`
Run with: `sudo docker compose -f docker-compose.yml up`
Edit the [.config](.config) with: `sudo docker exec -it tcl-core-560z-edit-config-main-1 sh`
and then `make menuconfig`

# CS4237B
The 560z uses a CS4237B sound chip. Some forum said to disable the quick boot from the
bios which you can reach by hold F1 and turning on the 560z. I did that, but the control
device which should have been in the list of PNP ISA devices with EISA ID CSC0010 still
wasn't there. I tried a bunch of things to make it appear, but it never did. In any case,
still disable the quick boot because I run with it disabled and with my modifications
to the cs4236 driver sound does end up working.

I remove `cport` and `cimage` from the snd cs4236 driver. See files here [6.12.11](./6.12.11/).
I also simplified and deleted code which would not run because the `chip->hardware` is
`WSS_HW_CS4237B`. I clarified many variables and methods and added comments.

## tools
See the [tools](./tools/) for scripts which automate many steps
to get and install the files generated in the docker containers.
I'm using this script to correctly load the modules, have sound and test sound:
```
#!/bin/sh
# Required for alsamixer to work.
tce-load -i alsa-config
# alsa depends on alsa-modules-KERNEL.tcz and will load them
tce-load -i alsa
tce-load -i mpg123
sudo cp /home/tc/configuration/asound.state /usr/local/etc/alsa/
sudo alsactl restore CS4237B
```
`/home/tc/configuration/asound.state` won't exist the first time.
You'll have to run manually:
```
tce-load -i alsa-config
tce-load -i alsa
alsamixer
```
and set the master volume and the pcm volume to 100. Then,
```
sudo alsactl store CS4237B
sudo cp /usr/local/etc/alsa/asound.state /home/tc/configuration/
```
You should then be able to `mpg123 your.mp3` to play a file.
Still no sound? Try `sudo alsactl init CS4237B`. I sometimes
have to do that maybe because some registers of the CS4237B are
set to the go to the wrong values...? Also unmute the sound
using the Fn and volume keys of your keyboard. Make sure you
hear the "beep" the volume up keybaoard key produces.

