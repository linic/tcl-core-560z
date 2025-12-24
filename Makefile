# Build the following for the 560z
# - bzImage
# - core.gz
# - ipv6-netfilter-x.y.z-tinycore-560z.tcz
# - net-modules-x.y.z-tinycore-560z.tcz
# - parport-modules-x.y.z-tinycore-560z.tcz
# - pcmcia-modules-x.y.z-tinycore-560z.tcz
# - usb-modules-x.y.z-tinycore-560z.tcz
# - wireless-x.y.z-tinycore-560z.tcz
# Patches the cs4236 module.

# Compatible with regular kernels from
# https://www.kernel.org/
# and SLTS kernels from
# https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git/refs/tags
# For more details about CIP support schedule see
# https://wiki.linuxfoundation.org/civilinfrastructureplatform/start

# Only set the CIP_NUMBER when your kernel is an SLTS CIP.
# For example 4.4.302-cip97
# CIP_NUMBER=97
# There are 2 ways to replace the modules in core.gz:
# 1. get core.gz, unpack it and remove the modules since it is rootfs.gz + modules.gz
# 2. get rootfs.gz directly
# Note: for 16.0beta1, core.gz doesn't exist yet. So rootfs.gz must be used.
# See the Dockerfile for more details about how the modules are replaced.
CORE_GZ=rootfs.gz
ITERATION=3
# This refers to the LOCAL_VERSION variable in the kernel .config file.
LOCAL_VERSION=-tinycore-560z
KERNEL_VERSION_TRIPLET=5.10.247
TCL_MAJOR_VERSION=16
TCL_RELEASE_TYPE=release
TCL_DOCKER_IMAGE_VERSION=16.x

all: edit build publish

edit:
	tools/edit-config.sh ${KERNEL_VERSION_TRIPLET}.${TCL_MAJOR_VERSION}.${ITERATION} ${TCL_DOCKER_IMAGE_VERSION} ${CIP_NUMBER}

trim:
	tools/trim.sh ${KERNEL_VERSION_TRIPLET}.${TCL_MAJOR_VERSION}.${ITERATION} ${TCL_RELEASE_TYPE} ${CORE_GZ}

build:
	tools/build-all.sh ${KERNEL_VERSION_TRIPLET}.${TCL_MAJOR_VERSION}.${ITERATION} ${TCL_RELEASE_TYPE} ${CORE_GZ} ${LOCAL_VERSION} ${TCL_DOCKER_IMAGE_VERSION} ${CIP_NUMBER}

publish:
	tools/publish.sh ${KERNEL_VERSION_TRIPLET}.${TCL_MAJOR_VERSION}.${ITERATION} ${LOCAL_VERSION} ${CIP_NUMBER}

