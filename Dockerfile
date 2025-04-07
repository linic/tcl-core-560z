# To be able to read all the commands outputs as they get executed:
# sudo docker compose --progress=plain -f docker-compose.yml build
ARG ITERATION_NUMBER
ARG KERNEL_BRANCH
ARG KERNEL_SUFFIX
ARG KERNEL_VERSION
ARG CORE_GZ
ARG TCL_MAJOR_VERSION_NUMBER
ARG TCL_RELEASE_TYPE
# You may get this warning:
# "WARN: InvalidDefaultArgInFrom: Default value for ARG linichotmailca/tcl-core-x86:$TCL_VERSION-x86 results in empty or invalid base image name"
# You can safely ignore it. The value from the docker-compose.yml loads correctly.
ARG TCL_VERSION
FROM linichotmailca/tcl-core-x86:$TCL_VERSION-x86 AS final
ARG ITERATION_NUMBER
ARG KERNEL_BRANCH
ARG KERNEL_SUFFIX
ARG KERNEL_VERSION
ARG CORE_GZ
ARG TCL_MAJOR_VERSION_NUMBER
ARG TCL_RELEASE_TYPE
ARG TCL_VERSION
ENV HOME_TC=/home/tc
WORKDIR $HOME_TC
# TCZs required to build the kernel
RUN tce-load -wi compiletc
RUN tce-load -wi ncursesw-dev
RUN tce-load -wi perl5
RUN tce-load -wi bash
RUN tce-load -wi bc
RUN tce-load -wi advcomp
# openssl-dev is required when building the kernel
RUN tce-load -wi openssl-dev

# There are 2 ways to replace the modules in core.gz:
# 1. get core.gz, unpack it and remove the modules since it is rootfs.gz + modules.gz
# 2. get rootfs.gz directly
# Note: for 16.0beta1, core.gz doesn't exist yet. So rootfs.gz must be used.
# For release versions, core.gz exists and can be used. The code below works with both.
# Getting core.gz for later
RUN wget http://tinycorelinux.net/$TCL_VERSION/x86/$TCL_RELEASE_TYPE/distribution_files/$CORE_GZ
RUN wget http://tinycorelinux.net/$TCL_VERSION/x86/$TCL_RELEASE_TYPE/distribution_files/$CORE_GZ.md5.txt
RUN md5sum -c $CORE_GZ.md5.txt
# Getting, editing and unpacking the official core.gz as explained in
# https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
ENV CORE_TEMP_PATH=$HOME_TC/coretmp
RUN mkdir $CORE_TEMP_PATH
WORKDIR $CORE_TEMP_PATH
RUN zcat $HOME_TC/$CORE_GZ | sudo cpio -i -H newc -d
# Removing the official modules since they can't be used with our custom kernel
ENV CORE_TEMP_MODULES_PATH=$CORE_TEMP_PATH/lib/modules
RUN if [ -d $CORE_TEMP_MODULES_PATH ]; then sudo rm -rf $CORE_TEMP_MODULES_PATH; fi
# For visual feedback of what has been extracted.
RUN ls $CORE_TEMP_PATH

# Getting kernel.tar.xz
WORKDIR $HOME_TC
ENV KERNEL_VERSION_NAME=linux-$KERNEL_VERSION
ENV KERNEL_SOURCE_PATH=$HOME_TC/$KERNEL_VERSION_NAME
ENV KERNEL_TAR_XZ=$KERNEL_VERSION_NAME.tar.xz
# installing curl installs the CA certificates and avoids using wget and trusting any certificate since kernel.org is in https.
RUN tce-load -wi curl
RUN curl --remote-name https://cdn.kernel.org/pub/linux/kernel/$KERNEL_BRANCH/$KERNEL_TAR_XZ
RUN tar x -f $KERNEL_TAR_XZ
# Making the kernel, the modules and installing them
WORKDIR $KERNEL_SOURCE_PATH
# NOTE 1: IMPORTANT! the .config file has to be owned by tc:staff otherwise the make commands
# don't load it because they don't have the permission and they default to a default
# config which breaks in a confusing way.
COPY --chown=tc:staff .config ./.config
COPY --chown=tc:staff .config-v5.x ./.config-v5.x
COPY --chown=tc:staff tools/pick-config.sh ./
RUN ./pick-config.sh $KERNEL_BRANCH
# Patch the cs4236 and wss files.
WORKDIR $KERNEL_SOURCE_PATH
COPY --chown=tc:staff cs4237b/patches $KERNEL_SOURCE_PATH/patches
COPY --chown=tc:staff cs4237b/patches-5.10.235 $KERNEL_SOURCE_PATH/patches-5.10.235
COPY --chown=tc:staff tools/pick-patches.sh ./
RUN ./pick-patches.sh $KERNEL_BRANCH
RUN patch -p1 < patches/cs4236.c.patch
RUN patch -p1 < patches/cs4236_lib.c.patch
RUN patch -p1 < patches/wss.h.patch
RUN patch -p1 < patches/wss_lib.c.patch
# Make the kernel
RUN make bzImage
# Make the modules
RUN make modules
ENV KERNEL_MODULES_INSTALL_PATH=$HOME_TC/modules
RUN mkdir $KERNEL_MODULES_INSTALL_PATH
RUN make INSTALL_MOD_PATH=$KERNEL_MODULES_INSTALL_PATH modules_install
# Continuing, editing and unpacking the official core.gz as explained in
# https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
# Adding our custom built modules which will work with our custom kernel
RUN if [ ! -d $CORE_TEMP_MODULES_PATH ]; then sudo mkdir -p $CORE_TEMP_MODULES_PATH; fi
RUN sudo cp -rv $KERNEL_MODULES_INSTALL_PATH/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX $CORE_TEMP_MODULES_PATH/
# Let's compress the modules with gzip and advdef since it is like that in the official core.gz
WORKDIR $CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX
COPY --chown=tc:staff --chmod=0755 compress_modules.sh . 
RUN sudo ./compress_modules.sh
RUN sudo rm ./compress_modules.sh
# edit modules.* files since they refer to the old .ko file and not the .ko.gz and won't load otherwise.
COPY --chown=tc:staff --chmod=0755 edit-modules.dep.order.sh .
RUN sudo ./edit-modules.dep.order.sh
RUN sudo rm ./edit-modules.dep.order.sh

# create the kernel.tclocal
COPY --chown=tc:staff --chmod=0755 create-kernel.tclocal.sh .
RUN sudo ./create-kernel.tclocal.sh $KERNEL_VERSION-$KERNEL_SUFFIX $CORE_TEMP_PATH
RUN sudo rm ./create-kernel.tclocal.sh
# source and build are there by default, but they're not needed
RUN if [ -d "source" ]; then sudo rm source; fi
RUN sudo rm build

# Extracting the sound files to create the equivalent alsa-modules-KERNEL.tcz file.
WORKDIR $HOME_TC
ENV ALSA_MODULES_TCZ_INSTALL_PATH=alsa-modules-$KERNEL_VERSION-$KERNEL_SUFFIX
ENV ALSA_MODULES_TCZ=$ALSA_MODULES_TCZ_INSTALL_PATH.tcz
ENV SOUND_INSTALL_PATH=$ALSA_MODULES_TCZ_INSTALL_PATH/usr/local/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/sound
ENV SOUND_MODULES_SOURCE=$CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/sound
RUN mkdir -p $SOUND_INSTALL_PATH
# Move the sound modules from core since we'll have them in the alsa-modules-KERNEL.tcz
RUN if [ -d $SOUND_MODULES_SOURCE ]; then sudo mv $SOUND_MODULES_SOURCE $SOUND_INSTALL_PATH; else echo "no $SOUND_MODULES_SOURCE" >> $SOUND_INSTALL_PATH/readme.txt; fi
RUN mksquashfs $ALSA_MODULES_TCZ_INSTALL_PATH $ALSA_MODULES_TCZ
RUN unsquashfs -l $ALSA_MODULES_TCZ

# Extracting the wireless files to create wireless-KERNEL.tcz file.
ENV WIRELESS_MODULES_TCZ_INSTALL_PATH=wireless-$KERNEL_VERSION-$KERNEL_SUFFIX
ENV WIRELESS_MODULES_TCZ=$WIRELESS_MODULES_TCZ_INSTALL_PATH.tcz
ENV DRIVERS_WIRELESS_INSTALL_PATH=$WIRELESS_MODULES_TCZ_INSTALL_PATH/usr/local/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/net/wireless
ENV DRIVERS_WIRELESS_SOURCE=$CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/net/wireless
RUN mkdir -p $DRIVERS_WIRELESS_INSTALL_PATH
# Move the net/wireless modules from core since we'll have them in the wireless-KERNEL.tcz
RUN if [ -d $DRIVERS_WIRELESS_SOURCE ]; then sudo mv $DRIVERS_WIRELESS_SOURCE $DRIVERS_WIRELESS_INSTALL_PATH; else echo "no $DRIVERS_WIRELESS_SOURCE" >> $DRIVERS_WIRELESS_INSTALL_PATH/readme.txt; fi
RUN mksquashfs $WIRELESS_MODULES_TCZ_INSTALL_PATH $WIRELESS_MODULES_TCZ
RUN unsquashfs -l $WIRELESS_MODULES_TCZ

# Extracting the ipv6 and netfilter files to create ipv6-netfilter-KERNEL.tcz file.
ENV IPV6_NETFILTER_MODULES_TCZ_INSTALL_PATH=ipv6-netfilter-$KERNEL_VERSION-$KERNEL_SUFFIX
ENV IPV6_NETFILTER_MODULES_TCZ=$IPV6_NETFILTER_MODULES_TCZ_INSTALL_PATH.tcz
ENV IPV6_NETFILTER_INSTALL_PATH=$IPV6_NETFILTER_MODULES_TCZ_INSTALL_PATH/usr/local/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/net
ENV IPV4_NETFILTER_MODULES_SOURCE=$CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/net/ipv4/netfilter
ENV IPV4_NETFILTER_MODULES_DESTINATION=$IPV6_NETFILTER_INSTALL_PATH/ipv4/netfilter
ENV NETFILTER_MODULES_SOURCE=$CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/net/netfilter
ENV NETFILTER_MODULES_DESTINATION=$IPV6_NETFILTER_INSTALL_PATH/netfilter
ENV IPV6_MODULES_SOURCE=$CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/net/ipv6
ENV IPV6_MODULES_DESTINATION=$IPV6_NETFILTER_INSTALL_PATH/ipv6
RUN mkdir -p $IPV6_NETFILTER_INSTALL_PATH
RUN mkdir -p $IPV6_NETFILTER_INSTALL_PATH/ipv4/netfilter
RUN mkdir -p $IPV6_NETFILTER_INSTALL_PATH/ipv6
RUN mkdir -p $IPV6_NETFILTER_INSTALL_PATH/netfilter
# Move the net/ipv4/netfilter, net/ipv6, net/netfilter modules from core since we'll have them in the ipv6-netfilter-KERNEL.tcz
RUN if [ -d $IPV4_NETFILTER_MODULES_SOURCE ]; then sudo mv $IPV4_NETFILTER_MODULES_SOURCE $IPV4_NETFILTER_MODULES_DESTINATION; else echo "no $IPV4_NETFILTER_MODULES_SOURCE" >> $IPV4_NETFILTER_MODULES_DESTINATION/readme.txt; fi
RUN if [ -d $NETFILTER_MODULES_SOURCE ]; then sudo mv $NETFILTER_MODULES_SOURCE $NETFILTER_MODULES_DESTINATION; else echo "no $NETFILTER_MODULES_SOURCE" >> $NETFILTER_MODULES_DESTINATION/readme.txt; fi
RUN if [ -d $IPV6_MODULES_SOURCE ]; then sudo mv $IPV6_MODULES_SOURCE $IPV6_MODULES_DESTINATION; else echo "no $IPV6_MODULES_SOURCE" >> $IPV6_MODULES_DESTINATION/readme.txt; fi
RUN mksquashfs $IPV6_NETFILTER_MODULES_TCZ_INSTALL_PATH $IPV6_NETFILTER_MODULES_TCZ
RUN unsquashfs -l $IPV6_NETFILTER_MODULES_TCZ

# Extracting the net files to create net-modules-KERNEL.tcz file.
ENV NET_MODULES_TCZ_INSTALL_PATH=net-modules-$KERNEL_VERSION-$KERNEL_SUFFIX
ENV NET_MODULES_TCZ=$NET_MODULES_TCZ_INSTALL_PATH.tcz
ENV NET_INSTALL_PATH=$NET_MODULES_TCZ_INSTALL_PATH/usr/local/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/net
ENV DRIVERS_NET_INSTALL_PATH=$NET_MODULES_TCZ_INSTALL_PATH/usr/local/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/net
RUN mkdir -p $NET_INSTALL_PATH
RUN mkdir -p $DRIVERS_NET_INSTALL_PATH
# Move the net and drivers/net modules from core since we'll have them in the net-modules-KERNEL.tcz
RUN sudo mv $CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/net $NET_INSTALL_PATH
RUN sudo mv $CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/net $DRIVERS_NET_INSTALL_PATH
RUN mksquashfs $NET_MODULES_TCZ_INSTALL_PATH $NET_MODULES_TCZ
RUN unsquashfs -l $NET_MODULES_TCZ

# Extracting the drivers/usb files to create usb-modules-KERNEL.tcz file.
ENV USB_MODULES_TCZ_INSTALL_PATH=usb-modules-$KERNEL_VERSION-$KERNEL_SUFFIX
ENV USB_MODULES_TCZ=$USB_MODULES_TCZ_INSTALL_PATH.tcz
ENV USB_INSTALL_PATH=$USB_MODULES_TCZ_INSTALL_PATH/usr/local/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/usb
RUN mkdir -p $USB_INSTALL_PATH
# Move the kernel/drivers/usb modules from core since we'll have them in the usb-modules-KERNEL.tcz
RUN sudo mv $CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/usb $USB_INSTALL_PATH
RUN mksquashfs $USB_MODULES_TCZ_INSTALL_PATH $USB_MODULES_TCZ
RUN unsquashfs -l $USB_MODULES_TCZ

# Extracting the drivers/pcmcia files to create pcmcia-modules-KERNEL.tcz file.
ENV PCMCIA_MODULES_TCZ_INSTALL_PATH=pcmcia-modules-$KERNEL_VERSION-$KERNEL_SUFFIX
ENV PCMCIA_MODULES_TCZ=$PCMCIA_MODULES_TCZ_INSTALL_PATH.tcz
ENV PCMCIA_INSTALL_PATH=$PCMCIA_MODULES_TCZ_INSTALL_PATH/usr/local/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/pcmcia
ENV PCMCIA_MODULES_SOURCE=$CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/pcmcia
RUN mkdir -p $PCMCIA_INSTALL_PATH
# Move the kernel/drivers/pcmcia modules from core since we'll have them in the pcmcia-modules-KERNEL.tcz
RUN if [ -d $PCMCIA_MODULES_SOURCE ]; then sudo mv $PCMCIA_MODULES_SOURCE $PCMCIA_INSTALL_PATH; else echo "no $PCMCIA_MODULES_SOURCE" >> $PCMCIA_INSTALL_PATH/readme.txt; fi
RUN mksquashfs $PCMCIA_MODULES_TCZ_INSTALL_PATH $PCMCIA_MODULES_TCZ
RUN unsquashfs -l $PCMCIA_MODULES_TCZ

# Extracting the drivers/parport files to create parport-modules-KERNEL.tcz file.
ENV PARPORT_MODULES_TCZ_INSTALL_PATH=parport-modules-$KERNEL_VERSION-$KERNEL_SUFFIX
ENV PARPORT_MODULES_TCZ=$PARPORT_MODULES_TCZ_INSTALL_PATH.tcz
ENV PARPORT_INSTALL_PATH=$PARPORT_MODULES_TCZ_INSTALL_PATH/usr/local/lib/modules/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/parport
ENV PARPORT_MODULES_SOURCE=$CORE_TEMP_MODULES_PATH/$KERNEL_VERSION-$KERNEL_SUFFIX/kernel/drivers/parport
RUN mkdir -p $PARPORT_INSTALL_PATH
# Move the kernel/drivers/parport modules from core since we'll have them in the parport-modules-KERNEL.tcz
RUN if [ -d $PARPORT_MODULES_SOURCE ]; then sudo mv $PARPORT_MODULES_SOURCE $PARPORT_INSTALL_PATH; else echo "no $PARPORT_MODULES_SOURCE" >> $PARPORT_INSTALL_PATH/readme.txt; fi
RUN mksquashfs $PARPORT_MODULES_TCZ_INSTALL_PATH $PARPORT_MODULES_TCZ
RUN unsquashfs -l $PARPORT_MODULES_TCZ

# Generate the custom core.gz file as explained in 
# https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
WORKDIR $CORE_TEMP_PATH
RUN  sudo find | sudo cpio -o -H newc | gzip -9 > $HOME_TC/core-$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER.gz
# Copying the bzImage which is the kernel
WORKDIR $HOME_TC
RUN cp $KERNEL_SOURCE_PATH/arch/x86/boot/bzImage $HOME_TC/bzImage-$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER
RUN ls -larth $HOME_TC/core-$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER.gz
RUN ls -larth $HOME_TC/bzImage-$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER
RUN ls -larth $HOME_TC/$NET_MODULES_TCZ
RUN ls -larth $HOME_TC/$ALSA_MODULES_TCZ
RUN ls -larth $HOME_TC/$USB_MODULES_TCZ
RUN ls -larth $HOME_TC/$PCMCIA_MODULES_TCZ
RUN ls -larth $HOME_TC/$PARPORT_MODULES_TCZ
COPY echo_sleep /
ENTRYPOINT ["/bin/sh", "/echo_sleep"]

