#!/bin/sh

###################################################################
# Copyright (C) 2025  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

# Check for dependencies.
if [ ! /home/tc/tools/ftp-get.sh ]; then
  echo "Please make an executable copy of ftp-get.sh available at "\
    "/home/tc/tools/"
  exit 1
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
  exit 3
fi

# The real work begins here.
export boot_options=$(cat /home/tc/configuration/boot-options)
export sda_tcz_files=$(cat /home/tc/configuration/sda-tcz-files)

if [ $# -eq 2 ]; then
	echo "Downloading and installing $1.$2..."
else
	echo "Enter kernel version x.y.z and 'tinycore version'.'iteration number'. Example: ftp-get-kernel.sh 6.12.11 15.8"
  exit 4
fi

# Copy the NAME-modules-KERNEL.tcz files and their md5.txt to the tce/optional where the other loadable tcz files are.
/home/tc/tools/ftp-get.sh alsa-modules-$1-tinycore-560z.tcz
/home/tc/tools/ftp-get.sh alsa-modules-$1-tinycore-560z.tcz.md5.txt
if md5sum -c alsa-modules-$1-tinycore-560z.tcz.md5.txt; then
  sudo cp -v alsa-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/
else
  echo "alsa-modules-$1-tinycore-560z.tcz failed validation!"
  exit 5
fi

/home/tc/tools/ftp-get.sh ipv6-netfilter-$1-tinycore-560z.tcz
/home/tc/tools/ftp-get.sh ipv6-netfilter-$1-tinycore-560z.tcz.md5.txt
if md5sum -c ipv6-netfilter-$1-tinycore-560z.tcz.md5.txt; then
  sudo cp -v ipv6-netfilter-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/
else
  echo "ipv6-netfilter-$1-tinycore-560z.tcz failed validation!"
  exit 6
fi

/home/tc/tools/ftp-get.sh net-modules-$1-tinycore-560z.tcz
/home/tc/tools/ftp-get.sh net-modules-$1-tinycore-560z.tcz.md5.txt
if md5sum -c net-modules-$1-tinycore-560z.tcz.md5.txt; then
  sudo cp -v net-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/
else
  echo "net-modules-$1-tinycore-560z.tcz failed validation!"
  exit 7
fi

/home/tc/tools/ftp-get.sh parport-modules-$1-tinycore-560z.tcz
/home/tc/tools/ftp-get.sh parport-modules-$1-tinycore-560z.tcz.md5.txt
if md5sum -c parport-modules-$1-tinycore-560z.tcz.md5.txt; then
  sudo cp -v parport-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/
else
  echo "parport-modules-$1-tinycore-560z.tcz failed validation!"
  exit 8
fi

/home/tc/tools/ftp-get.sh pcmcia-modules-$1-tinycore-560z.tcz
/home/tc/tools/ftp-get.sh pcmcia-modules-$1-tinycore-560z.tcz.md5.txt
if md5sum -c pcmcia-modules-$1-tinycore-560z.tcz.md5.txt; then
  sudo cp -v pcmcia-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/
else
  echo "pcmcia-modules-$1-tinycore-560z.tcz failed validation!"
  exit 9
fi

/home/tc/tools/ftp-get.sh usb-modules-$1-tinycore-560z.tcz
/home/tc/tools/ftp-get.sh usb-modules-$1-tinycore-560z.tcz.md5.txt
if md5sum -c usb-modules-$1-tinycore-560z.tcz.md5.txt; then
  sudo cp -v usb-modules-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/
else
  echo "usb-modules-$1-tinycore-560z.tcz failed validation!"
  exit 10
fi

/home/tc/tools/ftp-get.sh wireless-$1-tinycore-560z.tcz
/home/tc/tools/ftp-get.sh wireless-$1-tinycore-560z.tcz.md5.txt
if md5sum -c wireless-$1-tinycore-560z.tcz.md5.txt; then
  sudo cp -v wireless-$1-tinycore-560z.tcz* /mnt/$sda_tcz_files/tce/optional/
else
  echo "wireless-$1-tinycore-560z.tcz failed validation!"
  exit 11
fi

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
/home/tc/tools/ftp-get.sh bzImage-$1.$2.md5.txt
if md5sum -c bzImage-$1.$2.md5.txt; then
  sudo cp -v bzImage-$1.$2 /mnt/sda1/tce/boot/custom/
else
  echo "bzImage-$1.$2 failed validation!"
  exit 12
fi

/home/tc/tools/ftp-get.sh core-$1.$2.gz
/home/tc/tools/ftp-get.sh core-$1.$2.gz.md5.txt
if md5sum -c core-$1.$2.gz.md5.txt; then
  sudo cp -v core-$1.$2.gz /mnt/sda1/tce/boot/custom/
else
  echo "core-$1.$2.gz failed validation!"
  exit 13
fi

# Only backup the extlinux.conf if it hasn't been backed up yet.
if [ ! extlinux.conf.backup.before.$1.$2 ]; then
  sudo cp /mnt/sda1/tce/boot/extlinux/extlinux.conf ./extlinux.conf.backup.before.$1.$2
fi

# Add an entry to the boot menu to be able to boot this new kernel.
echo LABEL $1.$2 >> /mnt/sda1/tce/boot/extlinux/extlinux.conf
echo KERNEL /tce/boot/custom/bzImage-$1.$2 >> /mnt/sda1/tce/boot/extlinux/extlinux.conf
echo INITRD /tce/boot/custom/core-$1.$2.gz >> /mnt/sda1/tce/boot/extlinux/extlinux.conf
echo APPEND $boot_options >> /mnt/sda1/tce/boot/extlinux/extlinux.conf
echo >> /mnt/sda1/tce/boot/extlinux/extlinux.conf

