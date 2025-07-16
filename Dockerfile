# To be able to read all the commands outputs as they get executed:
# sudo docker compose --progress=plain -f docker-compose.yml build
ARG CORE_GZ
ARG CIP_NUMBER
ARG ITERATION_NUMBER
ARG KERNEL_BRANCH
ARG KERNEL_ID
ARG KERNEL_NAME
ARG KERNEL_TAR
ARG KERNEL_URL
ARG KERNEL_VERSION
ARG LOCALVERSION
ARG RELEASE_DIRECTORY
ARG RELEASE_VERSION
ARG TCL_DOCKER_IMAGE_VERSION
ARG TCL_RELEASE_TYPE
# You may get this warning:
# "WARN: InvalidDefaultArgInFrom: Default value for ARG linichotmailca/tcl-core-x86:$TCL_VERSION-x86 results in empty or invalid base image name"
# You can safely ignore it. The value from the docker-compose.yml loads correctly.
ARG TCL_VERSION
ARG VERSION_QUINTUPLET
FROM linichotmailca/tcl-core-x86:$TCL_DOCKER_IMAGE_VERSION-x86 AS final
ARG CORE_GZ
ARG CIP_NUMBER
ARG ITERATION_NUMBER
ARG KERNEL_BRANCH
ARG KERNEL_ID
ARG KERNEL_NAME
ARG KERNEL_TAR
ARG KERNEL_URL
ARG KERNEL_VERSION
ARG LOCALVERSION
ARG RELEASE_DIRECTORY
ARG RELEASE_VERSION
ARG TCL_RELEASE_TYPE
ARG TCL_VERSION
ARG VERSION_QUINTUPLET
ENV HOME_TC=/home/tc
ENV TOOLS=/home/tc/tools
WORKDIR $HOME_TC
COPY --chown=tc:staff tools/tce-load-requirements.sh $TOOLS/
RUN $TOOLS/tce-load-requirements.sh $KERNEL_BRANCH
ENV CORE_TEMP_PATH=$HOME_TC/coretmp

# NOTE 1: IMPORTANT! the .config file has to be owned by tc:staff otherwise the make commands
# don't load it because they don't have the permission and they default to a default
# config which breaks in a confusing way.
ENV KERNEL_CONFIGS=$HOME_TC/kernel_configs
COPY --chown=tc:staff .config $KERNEL_CONFIGS/.config
COPY --chown=tc:staff .config-v5.x $KERNEL_CONFIGS/.config-v5.x
COPY --chown=tc:staff .config-v4.x $KERNEL_CONFIGS/.config-v4.x
ENV CS4237B_PATCHES=$HOME_TC/cs4237b
COPY --chown=tc:staff cs4237b/patches $CS4237B_PATCHES/patches
COPY --chown=tc:staff cs4237b/patches-5.10.235 $CS4237B_PATCHES/patches-5.10.235
COPY --chown=tc:staff cs4237b/patches-4.4.302-cip97 $CS4237B_PATCHES/patches-4.4.302-cip97
ENV CACHE=$HOME_TC/cache
COPY --chown=tc:staff cache/$KERNEL_VERSION $CACHE/$KERNEL_VERSION
COPY --chown=tc:staff cache/rootfs $CACHE/rootfs
# Use the cache or build new bzImage, modules and .tcz files.
COPY --chown=tc:staff tools/* $TOOLS/
RUN $TOOLS/make-bzImage-modules-tczs.sh $VERSION_QUINTUPLET $LOCALVERSION $CIP_NUMBER

# Generate the custom core.gz file as explained in 
# https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
WORKDIR $CORE_TEMP_PATH
RUN  sudo find | sudo cpio -o -H newc | gzip -9 > $RELEASE_DIRECTORY/core-$RELEASE_VERSION.gz
RUN ls -larth $RELEASE_DIRECTORY
WORKDIR $HOME_TC
ENTRYPOINT ["/bin/sh", "/home/tc/tools/echo_sleep.sh"]

