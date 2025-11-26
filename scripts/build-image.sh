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
KERNEL_DIR="$ROOT_DIR/kernel"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build}"


NUMJOBS=${NUMJOBS:-$(nproc)}
DO_KERNEL_BUILD=1
DO_ROOTFS=1

sudo chmod +x "$ROOT_DIR/scripts/"*.sh

OUTDIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
  --no-kernel) DO_KERNEL_BUILD=0; shift;;
  --no-rootfs) DO_ROOTFS=0; shift;;
    -j) shift; NUMJOBS="$1"; shift;;
    --outdir) shift; OUTDIR="$1"; shift;;
    --clean) CLEAN=1; shift;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

echo "[+] build-image: kernel build=${DO_KERNEL_BUILD}, rootfs build=${DO_ROOTFS}, jobs=${NUMJOBS}"

if [ "$DO_KERNEL_BUILD" -eq 1 ]; then
  echo "[+] Building kernel (out-of-tree)"
  if [ -z "${OUTDIR}" ]; then
    OUTDIR="$BUILD_ROOT/kernel"
    echo "[i] Using default out-of-tree build directory: $OUTDIR"
  fi
  mkdir -p "$OUTDIR"
  KBUILD_OPTS=("O=$OUTDIR")
  if [ ! -f "$OUTDIR/.config" ]; then
    if [ -f "$KERNEL_DIR/.config" ]; then
      echo "[i] Copying existing source .config -> build/.config"
      cp "$KERNEL_DIR/.config" "$OUTDIR/.config"
    else
      echo "[i] Generating defconfig in build directory"
      make -C "$KERNEL_DIR" "${KBUILD_OPTS[@]}" defconfig
    fi
  else
    echo "[i] Reusing existing build directory .config"
    make -C "$KERNEL_DIR" "${KBUILD_OPTS[@]}" olddefconfig || true
  fi
  echo "[+] Compiling bzImage (jobs=$NUMJOBS)"
  set -x
  make -C "$KERNEL_DIR" "${KBUILD_OPTS[@]}" -j"$NUMJOBS" bzImage
  set +x
  SRC_BZ="$OUTDIR/arch/$(uname -m)/boot/bzImage"
  [ -f "$SRC_BZ" ] || SRC_BZ="$OUTDIR/arch/x86/boot/bzImage"
  if [ -f "$SRC_BZ" ]; then
    cp "$SRC_BZ" "$BUILD_ROOT/bzImage"
    echo "[+] Copied bzImage -> $BUILD_ROOT/bzImage"
  else
    echo "[-] bzImage not found after build"
    exit 1
  fi
fi
if [ "$DO_ROOTFS" -eq 1 ]; then
  echo "[+] Assembling Debian rootfs (non-interactive)"
  if [ -x "$ROOT_DIR/scripts/debootstrap-debian.sh" ]; then
    INSTALL_DESKTOP=1 bash "$ROOT_DIR/scripts/debootstrap-debian.sh"
  else
    echo "[-] Missing debootstrap helper: $ROOT_DIR/scripts/debootstrap-debian.sh"
    exit 1
  fi

  if [ -x "$ROOT_DIR/scripts/bootstrap-vorcore.sh" ]; then
    echo "[+] Bootstrapping Vorcore tooling"
    sudo bash "$ROOT_DIR/scripts/bootstrap-vorcore.sh" || {
      echo -e "\033[31m[FATAL] bootstrap-vorcore.sh failed\033[0m"; exit 1; }
  else
    echo -e "\033[31m[FATAL] Vorcore bootstrap script not present; skipping\033[0m"
    echo -e "\033[31m[EXIT CODE 1] {$ROOT_DIR/scripts/bootstrap-vorcore.sh}\033[0m"
    echo -e "\033[31m[FATAL] Aborting...\033[0m"
    exit 1
  fi
fi

echo "[+] build-image complete"

if [ "${BOOT_AFTER_BUILD:-0}" = "1" ]; then
  echo "[+] Auto-boot requested (BOOT_AFTER_BUILD=1)"
  bash "$ROOT_DIR/scripts/boot.sh"
else
  echo "[i] Build complete; set BOOT_AFTER_BUILD=1 to auto-boot next run."
fi

