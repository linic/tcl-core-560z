# To be able to read all the commands outputs as they get executed:
# sudo docker compose --progress=plain -f docker-compose.yml build
ARG TCL_VERSION
FROM linichotmailca/tcl-core-x86:$TCL_VERSION-x86 AS final
ARG KERNEL_BRANCH
ARG KERNEL_VERSION
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
# curl works better than wget to get the core.gz and kernel.tar.xz from the net.
RUN tce-load -wi curl
# Getting core.gz for later
ARG TCL_VERSION
RUN curl --remote-name http://tinycorelinux.net/$TCL_VERSION/x86/release/distribution_files/core.gz
# Getting kernel.tar.xz
ENV KERNEL_VERSION_NAME=linux-$KERNEL_VERSION
ENV KERNEL_SOURCE_PATH=$HOME_TC/$KERNEL_VERSION_NAME
ENV KERNEL_TAR_XZ=$KERNEL_VERSION_NAME.tar.xz
RUN curl --remote-name https://cdn.kernel.org/pub/linux/kernel/$KERNEL_BRANCH/$KERNEL_TAR_XZ
RUN tar x -f $KERNEL_TAR_XZ
# Making the kernel, the modules and installing them
WORKDIR $KERNEL_SOURCE_PATH
COPY .config ./.config
# IMPORTANT! the .config file has to be owned by tc:staff otherwise the make commands
# don't load it because they don't have the permission and they default to a default
# config which breaks in a confusing way.
RUN sudo chown tc:staff .config
RUN make bzImage
RUN make modules
ENV KERNEL_MODULES_INSTALL_PATH=$HOME_TC/modules
RUN mkdir $KERNEL_MODULES_INSTALL_PATH
RUN make INSTALL_MOD_PATH=$KERNEL_MODULES_INSTALL_PATH modules_install
# Getting, editing and unpacking the official core.gz as explained in
# https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
ENV CORE_TEMP_PATH=$HOME_TC/coretmp
RUN mkdir $CORE_TEMP_PATH
WORKDIR $CORE_TEMP_PATH
RUN zcat $HOME_TC/core.gz | sudo cpio -i -H newc -d
# Removing the official modules since they can't be used with our custom kernel
RUN sudo rm -rf $CORE_TEMP_PATH/lib/modules/*
WORKDIR $HOME_TC
# Adding our custom built modules which will work with our custom kernel
RUN sudo cp -r $KERNEL_MODULES_INSTALL_PATH/lib/modules/* $CORE_TEMP_PATH/lib/modules/
WORKDIR $CORE_TEMP_PATH/lib/modules/$KERNEL_VERSION-tinycore-560z
# Let's compress the modules with gzip and advdef since it is like that in the official core.gz
COPY compress_modules.sh . 
RUN sudo chown tc:staff compress_modules.sh
RUN chmod +x compress_modules.sh
RUN sudo ./compress_modules.sh
RUN sudo rm ./compress_modules.sh
# edit modules.* files since they refer to the old .ko file and not the .ko.gz and won't load otherwise.
COPY edit-modules.dep.order.sh .
RUN sudo chown tc:staff edit-modules.dep.order.sh
RUN chmod +x edit-modules.dep.order.sh
RUN sudo ./edit-modules.dep.order.sh
RUN sudo rm ./edit-modules.dep.order.sh
# create the kernel.tclocal
COPY create-kernel.tclocal.sh .
RUN sudo chown tc:staff create-kernel.tclocal.sh
RUN chmod +x create-kernel.tclocal.sh
RUN sudo ./create-kernel.tclocal.sh $KERNEL_VERSION-tinycore-560z $CORE_TEMP_PATH
RUN sudo rm ./create-kernel.tclocal.sh
# source and build are there by default, but they're not needed
RUN if [ -d "source" ]; then sudo rm source; fi
RUN sudo rm build
# Generate the custom core.gz file as explained in 
# https://wiki.tinycorelinux.net/doku.php?id=wiki:custom_kernel&s[]=custom&s[]=kernel
WORKDIR $CORE_TEMP_PATH
ARG TCL_MAJOR_VERSION_NUMBER
ARG ITERATION_NUMBER
RUN  sudo find | sudo cpio -o -H newc | gzip -9 > $HOME_TC/core-$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER.gz
# Copying the bzImage which is the kernel
WORKDIR $HOME_TC
RUN cp $KERNEL_SOURCE_PATH/arch/x86/boot/bzImage $HOME_TC/bzImage-$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER
RUN ls -larth $HOME_TC/core-$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER.gz
RUN ls -larth $HOME_TC/bzImage-$KERNEL_VERSION.$TCL_MAJOR_VERSION_NUMBER.$ITERATION_NUMBER
# Then if you docker compose build you'll be able to docker exec -it into it and move around or
# docker cp files out of it.
COPY echo_sleep /
ENTRYPOINT ["/bin/sh", "/echo_sleep"]

