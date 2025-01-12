# tcl-core-560z
tcl-core customized for the Thinkpad 560z. This is based on the `.config` of 
[TCL 12.0](http://tinycorelinux.net/12.x/x86/release/src/kernel/config-5.10.3-tinycore).

## Why?
The Thinkpad 560z I have has 64 MB of RAM. TCL Core 14.0 is the most recent version of TCL which can be 
supported without customizing the kernel and modules because the amount of RAM is too small and init won't 
start. By selecting only the kernel (and modules) features needed, it's possible to get a much smaller kernel 
and boot-up TCL core 15.0.

### Why the official TCL Core 15.0 won't start?
Even with a swap partition, TCL Core 15.0 tries to start `init` before loading the swap and since there is 
not enough memory without the swap, init fails with codes such as 
[init (error -26) with Core 15.0](https://forum.tinycorelinux.net/index.php/topic,27458.0.html) (and I also
got error -2 while testing various custom kernels and modules.

## How to use?
To build the custom linux kernel and core.gz: 
`sudo docker compose --progress=plain -f docker-compose.yml build`

To copy them out of a running container: 
`sudo docker compose -f docker-compose.yml up` and in another terminal 
`sudo docker exec tcl-core-560z-main-1:/home/tc ls` to see the file names and then 
`sudo docker cp tcl-core-560z-main-1:/home/tc/core_linux-5.10.232.gz .` and 
`sudo docker cp tcl-core-560z-main-1:/home/tc/bzImage_linux-5.10.232.gz .`

Get those files on the laptop in your preferred way. 
Then, edit `tce/boot/extlinux/extlinux.conf` and add a new entry to test these.

## edit-config
The Dockerfile.edit-config and docker-compose.edit-config.yml here can help edit the .config file which will 
be used to build the custom kernel.

Build with: `sudo docker compose --progress=plain -f docker-compose.yml build`
Run with: `sudo docker compose -f docker-compose.yml up`
Edit the .config with: `sudo docker exec -it tcl-core-560z-edit-config-main-1 sh` and then `make menuconfig`

## `.config`
`.config`: customized version of the official TCL `.config`
To understand the differences between `.config` and `slim.config` use `diff tinycore_configs/config-5.10.3-tinycore .config`
A short not exhaustive list and maybe not up to date of what has been disabled:
- USB storage devices
- Many filesystems such as BTRFS
- cpuid
- hybernate & standby
- acpi video
- many HID drivers

