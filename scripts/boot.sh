#!/bin/bash

# Copyright (c) Killian Zabinsky
# All rights reserved.
#
# You may modify this file for personal use only.
# Redistribution in any form is strictly prohibited
# without express written permission from the author.
#
# Modified by: None

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
KERNEL="$BUILD_DIR/bzImage"
DISK_IMG="$BUILD_DIR/vorosium.img"
LOG_FILE="$BUILD_DIR/boot.log"
MEMORY=1024
CMDLINE="console=ttyS0 root=/dev/vda rw loglevel=7 net.ifnames=0 biosdevname=0"

# Color functions
color() { printf "\033[%sm" "$1"; }
GREEN=$(color '1;32'); CYAN=$(color '1;36'); YELLOW=$(color '1;33'); RESET=$(color '0')
info() { echo -e "${CYAN}[INFO]${RESET} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*" | tee -a "$LOG_FILE"; }
fatal() { echo -e "\033[31m[FATAL]\033[0m $*" | tee -a "$LOG_FILE"; exit 1; }

mkdir -p "$BUILD_DIR"

# Locate kernel
if [ ! -f "$KERNEL" ]; then ALT="$ROOT_DIR/kernel/bzImage"; [ -f "$ALT" ] && KERNEL="$ALT"; fi
[ -f "$KERNEL" ] || fatal "Kernel not found: $KERNEL"
[ -s "$DISK_IMG" ] || fatal "Disk image missing or empty: $DISK_IMG"

info "Kernel: $KERNEL"
info "Disk image: $DISK_IMG"
info "Cmdline: $CMDLINE"

# Validate kernel config
KCFG=""
for c in "$ROOT_DIR/build/kernel/.config" "$ROOT_DIR/kernel/.config"; do [ -f "$c" ] && KCFG="$c" && break || true; done
kc_has() { [ -n "$KCFG" ] && grep -q "^$1=y" "$KCFG" 2>/dev/null; }
REQ_SYMS=(CONFIG_VIRTIO_BLK CONFIG_BLK_DEV CONFIG_EXT4_FS CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT CONFIG_PROC_FS CONFIG_SYSFS CONFIG_TMPFS)
if [ -n "$KCFG" ]; then
  info "Kernel config: $KCFG"
  for s in "${REQ_SYMS[@]}"; do kc_has "$s" || warn "Missing $s"; done
else
  warn "Kernel .config not found; skipping feature validation"
fi

# Launch QEMU
QEMU=(qemu-system-x86_64 -name VorosiumOS -kernel "$KERNEL" -m "$MEMORY" -serial mon:stdio -cpu host -smp 2 \
      -device virtio-net-pci,netdev=n0,mac=52:54:00:12:34:56 -netdev user,id=n0,hostfwd=tcp::2222-:22 \
      -device virtio-keyboard-pci -device virtio-mouse-pci -vga qxl \
      -device virtio-blk-pci,drive=vda -drive if=none,id=vda,file="$DISK_IMG",format=raw \
      -append "$CMDLINE")
[ -e /dev/kvm ] && QEMU+=( -enable-kvm )

echo -e "${GREEN}Executing:${RESET} ${QEMU[*]}"
trap 'echo -e "${GREEN}Shutdown.${RESET}"' EXIT
exec "${QEMU[@]}"
