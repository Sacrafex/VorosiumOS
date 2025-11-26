#!/bin/bash

BUSYBOX_VERSION="1.36.1"
RAMDISK_DIR="./ramdisk"
mkdir -p "$RAMDISK_DIR/bin"

wget https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2
tar xjf busybox-$BUSYBOX_VERSION.tar.bz2
cd busybox-$BUSYBOX_VERSION
make distclean
make defconfig
sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' .config
make -j$(nproc)
cp busybox "$RAMDISK_DIR/bin/"
cd "$RAMDISK_DIR/bin"
./busybox --install -s .
cd ../../

chmod +x "$RAMDISK_DIR/init"
cd "$RAMDISK_DIR"
find . | cpio -o -H newc | gzip > ../ramdisk.img
