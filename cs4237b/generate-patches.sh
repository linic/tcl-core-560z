#!/bin/sh

###################################################################
# Copyright (C) 2026  linic@hotmail.ca Subject to GPL-3.0 license.#
# https://github.com/linic/tcl-core-560z                          #
###################################################################

echo "Generating patches for $1"
SOURCE="source-$1"
PATCH="patches/patches-$1"
mkdir -pv patches-"$1"
diff -u $SOURCE/sound/isa/wss/wss_lib.c.orig $SOURCE/sound/isa/wss/wss_lib.c  > $PATCH/wss_lib.c.patch
diff -u $SOURCE/sound/isa/cs423x/cs4236_lib.c.orig $SOURCE/sound/isa/cs423x/cs4236_lib.c  > $PATCH/cs4236_lib.c.patch
diff -u $SOURCE/sound/isa/cs423x/cs4236.c.orig $SOURCE/sound/isa/cs423x/cs4236.c  > $PATCH/cs4236.c.patch
diff -u $SOURCE/include/sound/wss.h.orig $SOURCE/include/sound/wss.h  > $PATCH/wss.h.patch
sed -i '1,2s/source.*\/include\/sound\/wss.h.orig/a\/include\/sound\/wss.h/g' $PATCH/wss.h.patch
sed -i '1,2s/source.*\/include\/sound\/wss.h/b\/include\/sound\/wss.h/g' $PATCH/wss.h.patch
sed -i '1,2s/\([^ ]*\)\t.*/\1/' $PATCH/wss.h.patch
sed -i '1,2s/source.*\/sound\/isa\/wss\/wss_lib.c.orig/a\/sound\/isa\/wss\/wss_lib.c/g' $PATCH/wss_lib.c.patch
sed -i '1,2s/source.*\/sound\/isa\/wss\/wss_lib.c/b\/sound\/isa\/wss\/wss_lib.c/g' $PATCH/wss_lib.c.patch
sed -i '1,2s/\([^ ]*\)\t.*/\1/' $PATCH/wss_lib.c.patch
sed -i '1,2s/source.*\/sound\/isa\/cs423x\/cs4236_lib.c.orig/a\/sound\/isa\/cs423x\/cs4236_lib.c/g' $PATCH/cs4236_lib.c.patch
sed -i '1,2s/source.*\/sound\/isa\/cs423x\/cs4236_lib.c/b\/sound\/isa\/cs423x\/cs4236_lib.c/g' $PATCH/cs4236_lib.c.patch
sed -i '1,2s/\([^ ]*\)\t.*/\1/' $PATCH/cs4236_lib.c.patch
sed -i '1,2s/source.*\/sound\/isa\/cs423x\/cs4236.c.orig/a\/sound\/isa\/cs423x\/cs4236.c/g' $PATCH/cs4236.c.patch
sed -i '1,2s/source.*\/sound\/isa\/cs423x\/cs4236.c/b\/sound\/isa\/cs423x\/cs4236.c/g' $PATCH/cs4236.c.patch
sed -i '1,2s/\([^ ]*\)\t.*/\1/' $PATCH/cs4236.c.patch
