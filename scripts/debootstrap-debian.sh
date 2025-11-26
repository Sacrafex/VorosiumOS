#!/usr/bin/env bash

# Copyright (c) Killian Zabinsky
# All rights reserved.
#
# You may modify this file for personal use only.
# Redistribution in any form is strictly prohibited
# without express written permission from the author.
#
# Modified by: None

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build}"
IMG_PATH="$BUILD_ROOT/vorosium.img"

DEBIAN_SUITE="bookworm"
MIRROR_URL="http://deb.debian.org/debian"
IMAGE_SIZE_MB=${IMAGE_SIZE_MB:-2048}
ROOT_PASSWORD=${ROOT_PASSWORD:-root}

echo "[+] ROOT_DIR=$ROOT_DIR"
echo "[+] Image path: $IMG_PATH (${IMAGE_SIZE_MB}MB)"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[i] Installing dependency: $1"
    sudo apt-get update -y
    case "$1" in
      debootstrap) sudo apt-get install -y debootstrap;;
      mkfs.ext4) sudo apt-get install -y e2fsprogs;;
      chroot) sudo apt-get install -y chroot coreutils;;
      *) echo "[-] Unknown package for $1; please install manually"; exit 1;;
    esac
  fi
}

require debootstrap
require mkfs.ext4

sudo mkdir -p "$BUILD_ROOT"

echo "[+] Creating ext4 image (${IMAGE_SIZE_MB}MB)"
sudo rm -f "$IMG_PATH"
sudo dd if=/dev/zero of="$IMG_PATH" bs=1M count="$IMAGE_SIZE_MB" status=progress
sudo mkfs.ext4 -F -L rootfs "$IMG_PATH"

MNT_DIR=$(mktemp -d)
cleanup() { set +e; sudo umount -R "$MNT_DIR" 2>/dev/null || true; sudo rm -rf "$MNT_DIR" 2>/dev/null || true; }
trap cleanup EXIT

sudo mount -o loop "$IMG_PATH" "$MNT_DIR"

echo "[+] Debootstrap ($DEBIAN_SUITE) into image"
sudo debootstrap \
  --arch=amd64 \
  --components=main,contrib,non-free-firmware \
  --include=systemd-sysv,sudo,ca-certificates,net-tools,iproute2,ifupdown,dialog,isc-dhcp-client,openssh-server,vim,less \
  "$DEBIAN_SUITE" "$MNT_DIR" "$MIRROR_URL"

ensure_dynamic_loader_exec() {
  local candidates=(
    "$MNT_DIR/lib64/ld-linux-x86-64.so.2"
    "$MNT_DIR/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
    "$MNT_DIR/usr/lib64/ld-linux-x86-64.so.2"
  )
  for p in "${candidates[@]}"; do
    if [ -e "$p" ]; then
      sudo chmod +x "$p" || true
      return 0
    fi
  done
  echo "[w] Dynamic loader not found; chroot may fail"
}

ensure_dynamic_loader_exec

echo "[+] Basic configuration"

# fstab mount virtual filesystems
sudo tee "$MNT_DIR/etc/fstab" >/dev/null <<'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
proc            /proc           proc    defaults          0       0
sysfs           /sys            sysfs   defaults          0       0
devpts          /dev/pts        devpts  gid=5,mode=620    0       0
tmpfs           /run            tmpfs   defaults          0       0
tmpfs           /tmp            tmpfs   defaults          0       0
EOF

# Enable networking with DHCP on eth0
sudo bash -c "cat > \"$MNT_DIR/etc/network/interfaces\" <<'EOF'
source-directory /etc/network/interfaces.d

auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

auto enp0s3
allow-hotplug enp0s3
iface enp0s3 inet dhcp
EOF"

echo "vorosium" | sudo tee "$MNT_DIR/etc/hostname" >/dev/null

sudo tee "$MNT_DIR/etc/hosts" >/dev/null <<'EOF'
127.0.0.1	localhost
127.0.1.1	vorosium

::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

sudo mkdir -p "$MNT_DIR/etc/systemd/system/getty@ttyS0.service.d"
sudo tee "$MNT_DIR/etc/systemd/system/getty@ttyS0.service.d/override.conf" >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 115200,38400,9600 ttyS0 linux
EOF

sudo chroot "$MNT_DIR" /bin/bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"
sudo chroot "$MNT_DIR" /bin/bash -c "systemctl enable ssh || true"
sudo chroot "$MNT_DIR" /bin/bash -c "systemctl enable networking || true"

if ! sudo grep -q '^ttyS0$' "$MNT_DIR/etc/securetty" 2>/dev/null; then
  echo ttyS0 | sudo tee -a "$MNT_DIR/etc/securetty" >/dev/null || true
fi

echo "[+] Installing wlroots-based desktop (sway + seatd + foot + mesa)"
sudo chroot "$MNT_DIR" /bin/bash -c "apt-get update && \
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
sway swaybg swayidle seatd foot wayland-protocols xwayland \
mesa-utils libgl1-mesa-dri libgbm1 libdrm2 dbus-user-session \
fonts-dejavu-core git curl"

DESKTOP_USER="vorosium"
DESKTOP_PASS="vorosium"

sudo chroot "$MNT_DIR" /bin/bash -c "getent group seatd >/dev/null || groupadd -r seatd"
sudo chroot "$MNT_DIR" /bin/bash -c "getent group render >/dev/null || groupadd -r render"
sudo chroot "$MNT_DIR" /bin/bash -c "id -u $DESKTOP_USER >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,video,input,render,seatd $DESKTOP_USER"
sudo chroot "$MNT_DIR" /bin/bash -c "echo '$DESKTOP_USER:$DESKTOP_PASS' | chpasswd"
sudo chroot "$MNT_DIR" /bin/bash -c "systemctl enable seatd || true"

echo "[+] Finalizing image"
sudo umount "$MNT_DIR"
sudo chown "${SUDO_UID:-$(id -u)}":"${SUDO_GID:-$(id -g)}" "$IMG_PATH" || true
sudo chmod 664 "$IMG_PATH" || true
echo "[+] Image ready: $IMG_PATH"
echo "[i] Boot with: ./scripts/boot.sh"