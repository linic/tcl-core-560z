#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

# Check for dependencies.
if [ ! /home/tc/tools/ftp-get.sh ]; then
  echo "Please make an executable copy of ftp-get.sh available at "\
    "/home/tc/tools/"
  exit 2
fi

if [ ! /home/tc/configuration/boot-options ]; then
  echo "Please create the /home/tc/configuration/boot-options "\
    "file and add the boot options you need."
  exit 2
fi

if [ ! /home/tc/configuration/sda-tcz-files ]; then
  echo "Please create the /home/tc/configuration/sda-tcz-files "\
    "file and add the 'sdaX' (replace X with a number) where the "\
    ".tcz files are."
  exit 2
fi

# The real work begins here.
export boot_options=$(cat /home/tc/configuration/boot-options)
export sda_tcz_files=$(cat /home/tc/configuration/sda-tcz-files)

if [ $# -eq 2 ]; then
	echo "Downloading and installing $1.$2..."
else
	echo "Enter kernel version x.y.z and 'tinycore version'.'iteration number'. Example: ftp-get-kernel.sh 6.12.11 15.8"
  exit 2
fi

# Copy the NAME-modules-KERNEL.tcz files and their md5.txt to the tce/optional where the other loadable tcz files are.
/home/tc/tools/ftp-get.sh alsa-modules-$1-tinycore-560z.tcz
ls -larth alsa-modules-$1-tinycore-560z.tcz
md5sum alsa-modules-$1-tinycore-560z.tcz > alsa-modules-$1-tinycore-560z.tcz.md5.txt
cat alsa-modules-$1-tinycore-560z.tcz.md5.txt
sudo cp -v alsa-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/

/home/tc/tools/ftp-get.sh net-modules-$1-tinycore-560z.tcz
ls -larth net-modules-$1-tinycore-560z.tcz
md5sum net-modules-$1-tinycore-560z.tcz > net-modules-$1-tinycore-560z.tcz.md5.txt
cat net-modules-$1-tinycore-560z.tcz.md5.txt
sudo cp -v net-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/

/home/tc/tools/ftp-get.sh parport-modules-$1-tinycore-560z.tcz
ls -larth parport-modules-$1-tinycore-560z.tcz
md5sum parport-modules-$1-tinycore-560z.tcz > parport-modules-$1-tinycore-560z.tcz.md5.txt
cat parport-modules-$1-tinycore-560z.tcz.md5.txt
sudo cp -v parport-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/

/home/tc/tools/ftp-get.sh pcmcia-modules-$1-tinycore-560z.tcz
ls -larth pcmcia-modules-$1-tinycore-560z.tcz
md5sum pcmcia-modules-$1-tinycore-560z.tcz > pcmcia-modules-$1-tinycore-560z.tcz.md5.txt
cat pcmcia-modules-$1-tinycore-560z.tcz.md5.txt
sudo cp -v pcmcia-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/

/home/tc/tools/ftp-get.sh usb-modules-$1-tinycore-560z.tcz
ls -larth usb-modules-$1-tinycore-560z.tcz
md5sum usb-modules-$1-tinycore-560z.tcz > usb-modules-$1-tinycore-560z.tcz.md5.txt
cat usb-modules-$1-tinycore-560z.tcz.md5.txt
sudo cp -v usb-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/

# Mount the sda1 partition which should be the one used for booting.
# vmlinuz/bzImage, core.gz and extlinux.conf should be there.
if mount | grep -q "^/dev/sda1"; then
	echo "/dev/sda1 is mounted"
else
	sudo mount /dev/sda1
fi

# Copy the core and bzImage to a directory inside tce/boot/ or any place where it can be read
# at boot time.
/home/tc/tools/ftp-get.sh bzImage-$1.$2
ls -larth bzImage-$1.$2
md5sum bzImage-$1.$2 > bzImage-$1.$2.md5.txt
cat bzImage-$1.$2.md5.txt
sudo cp -v bzImage-$1.$2 /mnt/sda1/tce/boot/custom/

/home/tc/tools/ftp-get.sh core-$1.$2.gz
ls -larth core-$1.$2.gz
md5sum core-$1.$2.gz > core-$1.$2.gz.md5.txt
cat core-$1.$2.gz.md5.txt
sudo cp -v core-$1.$2.gz /mnt/sda1/tce/boot/custom/

# Only backup the extlinux.conf if it hasn't been backed up yet.
if [ ! extlinux.conf.backup.before.$1.$2 ]; then
  sudo cp /mnt/sda1/tce/boot/extlinux/extlinux.conf ./extlinux.conf.backup.before.$1.$2
fi

# Add an entry to the boot menu to be able to boot this new kernel.
echo LABEL $1.$2 >> /mnt/sda1/tce/boot/extlinux/extlinux.conf
echo KERNEL /tce/boot/custom/bzImage-$1.$2 >> /mnt/sda1/tce/boot/extlinux/extlinux.conf
echo INITRD /tce/boot/custom/core-$1.$2.gz >> /mnt/sda1/tce/boot/extlinux/extlinux.conf
echo APPEND $boot-options >> /mnt/sda1/tce/boot/extlinux/extlinux.conf
echo >> /mnt/sda1/tce/boot/extlinux/extlinux.conf

