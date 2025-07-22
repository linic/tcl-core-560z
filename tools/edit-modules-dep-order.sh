#!/bin/sh

set -e
trap 'echo "Error on line $LINENO"' ERR

# Replaces 'build/' with 'kernel/' and '.ko' with '.ko.gz' in modules.dep
# See https://github.com/on-prem/tinycore-kernel, copied from there: "The modules.dep file should point to
# .ko.gz kernel modules, but Linux compiles them as .ko by default. The Makefile in this repo gzips all
# modules, and then performs a sed on the newly built modules.dep to ensure it also contains .ko.gz entries."
# Since I do run gzip and advdef to compress each module, each entry refering to a .ko file needs to be
# changed to .ko .gz.

# modules.dep is the only modules file I found refering to the build folder.
# Also, the first line is a .ko.cmd file which doesn't exist in the kernel/ folder. So I remove it.
sed -i '/.ko.cmd/d; s/build\//kernel\//g; s/.ko/.ko.gz/g' modules.dep

# This one refers to kernel and just needs .ko updated to .gz
# About this file, https://www.kernel.org/doc/Documentation/kbuild/kbuild.txt
# modules.order
# --------------------------------------------------
# This file records the order in which modules appear in Makefiles. This
# is used by modprobe to deterministically resolve aliases that match
# multiple modules.
sed -i 's/.ko/.ko.gz/g' modules.order

