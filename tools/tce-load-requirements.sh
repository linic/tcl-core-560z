#!/bin/sh

# TCZs required to build the kernel
tce-load -wi advcomp
tce-load -wi bash
tce-load -wi bc
tce-load -wi compiletc
tce-load -wi perl5
# openssl-dev is required when building the kernel
tce-load -wi openssl-dev
# Installing curl installs the CA certificates and then the
# certificates of https://www.kernel.org/ and
# https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git/snapshot/
# are correctly validated.
# A workaround when not using curl is to use wget and its option to trust any certificate.
tce-load -wi curl

# Failed attempt at using an older ncurses so that make menuconfig would work. It does not.
#if [ $1 = "v4.x" ]; then
  # 4.4.302-cip97 make menuconfig works with the ncurses from 7.x and not the ones in the current
#  echo "KERNEL_BRANCH is $1, getting the old ncurses-dev.tcz and its dependencies from tinycore 7.x..."
#  curl --remote-name http://tinycorelinux.net/7.x/x86/tcz/ncurses.tcz
#  curl --remote-name http://tinycorelinux.net/7.x/x86/tcz/ncurses.tcz.md5.txt
#  curl --remote-name http://tinycorelinux.net/7.x/x86/tcz/ncurses-dev.tcz
#  curl --remote-name http://tinycorelinux.net/7.x/x86/tcz/ncurses-dev.tcz.dep
#  curl --remote-name http://tinycorelinux.net/7.x/x86/tcz/ncurses-dev.tcz.md5.txt
#  tce-load -i ncurses-dev
#else
  # 5.10.235 and v6.x kernels make menuconfig work with the version matching the tinycore release (for example TCL 16)
tce-load -wi ncursesw-dev
#fi

