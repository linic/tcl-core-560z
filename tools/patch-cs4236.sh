#!/bin/sh

patch -p1 < patches/cs4236.c.patch
patch -p1 < patches/cs4236_lib.c.patch
patch -p1 < patches/wss.h.patch
patch -p1 < patches/wss_lib.c.patch

