#!/bin/sh
# See https://github.com/on-prem/tinycore-kernel/blob/master/Makefile#L101C91-L101C101 ,
# and https://github.com/on-prem/tinycore-kernel?tab=readme-ov-file#kernel-seems-to-boot-but-cant-mount-loop-or-disks
# copied here "The kernel.tclocal symlink is also needed for kernel module extensions to be loaded."
echo $1
echo $2
ln -sf /usr/local/lib/modules/$1/kernel $2/lib/modules/$1/kernel.tclocal

