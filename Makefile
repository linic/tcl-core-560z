# Build bzImage, core.gz, net-modules-6.12.11-tinycore-560z.tcz,
# parport-modules-6.12.11-tinycore-560z.tcz, pcmcia-modules-6.12.11-tinycore-560z.tcz,
# usb-modules-6.12.11-tinycore-560z.tcz for the 560z.

# There are 2 ways to replace the modules in core.gz:
# 1. get core.gz, unpack it and remove the modules since it is rootfs.gz + modules.gz
# 2. get rootfs.gz directly
# Note: for 16.0beta1, core.gz doesn't exist yet. So rootfs.gz must be used.
# See the Dockerfile for more details about how the modules are replaced.
CORE_GZ=rootfs.gz

ITERATION=7
LINUX_KERNEL_VERSION=6.13.7
TCL_MAJOR_VERSION=16
TCL_RELEASE_TYPE=release_candidates

all: edit build publish

edit:
	tools/edit-config.sh ${LINUX_KERNEL_VERSION}.${TCL_MAJOR_VERSION}.${ITERATION}

trim:
	tools/trim.sh ${LINUX_KERNEL_VERSION}.${TCL_MAJOR_VERSION}.${ITERATION} ${TCL_RELEASE_TYPE} ${CORE_GZ}

build:
	tools/build-all.sh ${LINUX_KERNEL_VERSION}.${TCL_MAJOR_VERSION}.${ITERATION} ${TCL_RELEASE_TYPE} ${CORE_GZ}

publish:
	tools/publish.sh ${LINUX_KERNEL_VERSION}.${TCL_MAJOR_VERSION}.${ITERATION}
