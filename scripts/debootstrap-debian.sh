#!/usr/bin/env bash

set -euo pipefail

# Copyright (c) Killian Zabinsky
# All rights reserved.
#
# You may modify this file for personal use only.
# Redistribution in any form is strictly prohibited
# without express written permission from the author.
#
# Modified by: None

# Build a minimal Debian (bookworm) rootfs using debootstrap and pack it into an ext4 image for the OS.
# By default the script writes to kernel/build/, but if the environment variable BUILD_ROOT
# is set, it will use $BUILD_ROOT/kernel and $BUILD_ROOT/debian-rootfs so files are centralized and
# all generated files under a top-level build/ directory.

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
KERNEL_DIR="$ROOT_DIR/kernel"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/kernel/build}"
BUILD_DIR="$BUILD_ROOT/kernel"
ROOTFS_DIR="$BUILD_DIR/debian-rootfs"
IMG_PATH="$BUILD_DIR/debian.img"

DEBIAN_SUITE="bookworm"
MIRROR_URL="http://deb.debian.org/debian"
IMAGE_SIZE_MB=${IMAGE_SIZE_MB:-2048} # default 2GiB
ROOT_PASSWORD=${ROOT_PASSWORD:-root}

echo "[+] Using ROOT_DIR=$ROOT_DIR"
echo "[+] Using ROOTFS_DIR=$ROOTFS_DIR"
echo "[+] Target image: $IMG_PATH (${IMAGE_SIZE_MB}MB)"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[i] Installing dependency: $1"
    sudo apt-get update -y
    case "$1" in
      debootstrap) sudo apt-get install -y debootstrap;;
      chroot) sudo apt-get install -y chroot coreutils;;
      mkfs.ext4) sudo apt-get install -y e2fsprogs;;
      mkswap) sudo apt-get install -y util-linux;;
      rsync) sudo apt-get install -y rsync;;
      *) echo "[-] Unknown package for $1; please install manually"; exit 1;;
    esac
  fi
}

require debootstrap
require mkfs.ext4
require rsync

sudo mkdir -p "$ROOTFS_DIR"
sudo mkdir -p "$BUILD_DIR"

ensure_dynamic_loader_exec() {
  local candidates=(
    "$ROOTFS_DIR/lib64/ld-linux-x86-64.so.2"
    "$ROOTFS_DIR/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
    "$ROOTFS_DIR/usr/lib64/ld-linux-x86-64.so.2"
  )
  for p in "${candidates[@]}"; do
    if [ -e "$p" ]; then
      echo "[i] Ensuring dynamic loader is executable: $p"
      sudo chmod +x "$p" || true
      return 0
    fi
  done
  echo "[w] dynamic loader not found in rootfs; chroot may fail"
}

if [ ! -f "$ROOTFS_DIR/.debootstrap_complete" ]; then
  echo "[+] Running debootstrap ($DEBIAN_SUITE) into $ROOTFS_DIR"
  sudo debootstrap \
    --arch=amd64 \
    --components=main,contrib,non-free-firmware \
    --include=systemd-sysv,sudo,ca-certificates,net-tools,iproute2,ifupdown,dialog,isc-dhcp-client,openssh-server,vim,less \
    "$DEBIAN_SUITE" "$ROOTFS_DIR" "$MIRROR_URL"
  sudo touch "$ROOTFS_DIR/.debootstrap_complete"
else
  echo "[i] debootstrap already completed; skipping"
fi

echo "[+] Configuring rootfs"

# fstab mount virtual filesystems
sudo tee "$ROOTFS_DIR/etc/fstab" >/dev/null <<'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
proc            /proc           proc    defaults          0       0
sysfs           /sys            sysfs   defaults          0       0
devpts          /dev/pts        devpts  gid=5,mode=620    0       0
tmpfs           /run            tmpfs   defaults          0       0
tmpfs           /tmp            tmpfs   defaults          0       0
EOF

# Enable networking with DHCP on eth0
sudo tee "$ROOTFS_DIR/etc/network/interfaces" >/dev/null <<'EOF'
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Bring up primary NIC automatically with DHCP
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
EOF

# Set hostname
echo "vorosium" | sudo tee "$ROOTFS_DIR/etc/hostname" >/dev/null

# Hosts
sudo tee "$ROOTFS_DIR/etc/hosts" >/dev/null <<'EOF'
127.0.0.1	localhost
127.0.1.1	vorosium

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Getty on serial
sudo mkdir -p "$ROOTFS_DIR/etc/systemd/system/getty@ttyS0.service.d"
sudo tee "$ROOTFS_DIR/etc/systemd/system/getty@ttyS0.service.d/override.conf" >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 115200,38400,9600 ttyS0 linux
EOF

# Make sure the dynamic linker is executable before using chroot
ensure_dynamic_loader_exec

# Root password and SSH adjustments
sudo chroot "$ROOTFS_DIR" /bin/bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"
sudo chroot "$ROOTFS_DIR" /bin/bash -c "systemctl enable ssh || true"
sudo chroot "$ROOTFS_DIR" /bin/bash -c "systemctl enable networking || true"

# Allow serial console in securetty
if ! sudo grep -q '^ttyS0$' "$ROOTFS_DIR/etc/securetty" 2>/dev/null; then
  echo ttyS0 | sudo tee -a "$ROOTFS_DIR/etc/securetty" >/dev/null || true
fi

  # ---------- Desktop (wlroots/sway) ----------
  echo "[+] Installing wlroots-based desktop (sway + seatd + foot + mesa)"
  sudo chroot "$ROOTFS_DIR" /bin/bash -c "apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    sway swaybg swayidle \
    seatd \
    foot \
    wayland-protocols \
    xwayland \
    mesa-utils libgl1-mesa-dri libgbm1 libdrm2 \
    dbus-user-session \
    fonts-dejavu-core"

  # Create a regular user and grant groups for graphics/input
  DESKTOP_USER="vorosium"
  DESKTOP_PASS="vorosium"
  
  sudo chroot "$ROOTFS_DIR" /bin/bash -c "getent group seatd >/dev/null || groupadd -r seatd"
  sudo chroot "$ROOTFS_DIR" /bin/bash -c "getent group render >/dev/null || groupadd -r render"
  sudo chroot "$ROOTFS_DIR" /bin/bash -c "id -u $DESKTOP_USER >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,video,input,render,seatd $DESKTOP_USER"
  sudo chroot "$ROOTFS_DIR" /bin/bash -c "echo '$DESKTOP_USER:$DESKTOP_PASS' | chpasswd"

  # Enable seatd service
  sudo chroot "$ROOTFS_DIR" /bin/bash -c "systemctl enable seatd || true"

  # Systemd unit to auto-start sway on tty1 for the desktop user
  sudo tee "$ROOTFS_DIR/etc/systemd/system/sway@.service" >/dev/null <<'EOF'
  [Unit]
  Description=Sway compositor for %i
  After=seatd.service systemd-user-sessions.service
  Wants=seatd.service

  [Service]
  User=%i
  PAMName=login
  TTYPath=/dev/tty1
  TTYReset=yes
  TTYVHangup=yes
  StandardInput=tty
  StandardOutput=journal
  StandardError=journal
  Environment=XDG_RUNTIME_DIR=/run/user/%U
  Environment=WLR_RENDERER_ALLOW_SOFTWARE=1
  ExecStartPre=/bin/mkdir -p /run/user/%U
  ExecStartPre=/bin/chown %U:%U /run/user/%U
  ExecStartPre=/bin/chmod 700 /run/user/%U
  ExecStart=/usr/bin/seatd-launch /usr/bin/sway
  Restart=on-failure
  RestartSec=2s

  [Install]
  WantedBy=multi-user.target
  EOF

  # Disable getty on tty1 to avoid conflicts with our sway@ service and enable sway autostart
  sudo chroot "$ROOTFS_DIR" /bin/bash -c "systemctl disable getty@tty1 || true; systemctl enable sway@${DESKTOP_USER} || true"

  # Provide a minimal sway config for the user
  sudo mkdir -p "$ROOTFS_DIR/home/$DESKTOP_USER/.config/sway"
  sudo tee "$ROOTFS_DIR/home/$DESKTOP_USER/.config/sway/config" >/dev/null <<'EOF'
include /etc/sway/config
exec_always foot
output * bg #000000 solid_color
EOF
  sudo chroot "$ROOTFS_DIR" /bin/bash -c "mkdir -p /home/$DESKTOP_USER/.config/sway && chown -R $DESKTOP_USER:$DESKTOP_USER /home/$DESKTOP_USER/.config"

# Resize image creation if requested
echo "[+] Creating ext4 image at $IMG_PATH (${IMAGE_SIZE_MB}MB)"
sudo rm -f "$IMG_PATH"
sudo dd if=/dev/zero of="$IMG_PATH" bs=1M count="$IMAGE_SIZE_MB" status=progress
sudo mkfs.ext4 -F -L rootfs "$IMG_PATH"

MNT_DIR=$(mktemp -d)
cleanup() {
  set +e
  sudo umount -R "$MNT_DIR" 2>/dev/null || true
  sudo rm -rf "$MNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount -o loop "$IMG_PATH" "$MNT_DIR"
echo "[+] Copying rootfs into image (this may take a while)"
sudo rsync -aHAX --delete "$ROOTFS_DIR"/ "$MNT_DIR"/
sync
sudo umount "$MNT_DIR"

echo "[+] Debian image ready: $IMG_PATH"
sudo chown "${SUDO_UID:-$(id -u)}":"${SUDO_GID:-$(id -g)}" "$IMG_PATH" || true
sudo chmod 664 "$IMG_PATH" || true
echo "[i] You can now boot it with: ./scripts/boot.sh"