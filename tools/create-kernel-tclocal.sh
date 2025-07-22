#!/bin/sh

set -e
trap 'echo "Error on line $LINENO"' ERR

# See https://github.com/on-prem/tinycore-kernel/blob/master/Makefile#L101C91-L101C101 ,
# and https://github.com/on-prem/tinycore-kernel?tab=readme-ov-file#kernel-seems-to-boot-but-cant-mount-loop-or-disks
# copied here "The kernel.tclocal symlink is also needed for kernel module extensions to be loaded."
echo "Creating kernel.tclocal symbolic link for /usr/local/lib/modules/$1/kernel $2/lib/modules/$1/kernel.tclocal"
mkdir -p $2/lib/modules/$1
ln -sf /usr/local/lib/modules/$1/kernel $2/lib/modules/$1/kernel.tclocal

