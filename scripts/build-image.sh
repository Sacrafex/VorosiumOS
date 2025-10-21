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

# - builds the kernel (bzImage) if needed
# - runs scripts/debootstrap-debian.sh to produce kernel/build/debian.img

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
KERNEL_DIR="$ROOT_DIR/kernel"
BUILD_ROOT="$ROOT_DIR/build"
BUILD_SCRIPT="$ROOT_DIR/scripts/debootstrap-debian.sh"

NUMJOBS=${NUMJOBS:-$(nproc)}
DO_KERNEL_BUILD=1
DO_DEBOOTSTRAP=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -h|--help        Show help
  --no-kernel       Skip kernel build
  --no-rootfs       Skip building the debian rootfs image
  -j N              Parallel jobs for kernel build (default: $NUMJOBS)
  --outdir PATH     Use an out-of-tree kernel build directory (passed as O=PATH)
  --clean           Clean kernel build outputs before building

This script will build the kernel bzImage (kernel/bzImage) and then run
the debootstrap script to produce kernel/build/debian.img.
EOF
}

OUTDIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --no-kernel) DO_KERNEL_BUILD=0; shift;;
    --no-rootfs) DO_DEBOOTSTRAP=0; shift;;
    -j) shift; NUMJOBS="$1"; shift;;
    --outdir) shift; OUTDIR="$1"; shift;;
    --clean) CLEAN=1; shift;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

echo "[+] SacrOS build-image: kernel build=${DO_KERNEL_BUILD}, rootfs=${DO_DEBOOTSTRAP}, jobs=${NUMJOBS}"

if [ "$DO_KERNEL_BUILD" -eq 1 ]; then
  echo "[+] Preparing to build kernel"
  if [ -z "${OUTDIR}" ]; then
    OUTDIR="$BUILD_ROOT/kernel"
    echo "[i] No --outdir supplied; defaulting out-of-tree kernel build to: $OUTDIR"
  else
    echo "[i] Using out-of-tree build directory: $OUTDIR"
  fi
  mkdir -p "$OUTDIR"
  KBUILD_OPTS=("O=$OUTDIR")

  echo "[+] Ensuring kernel out-of-tree build directory is clean: $OUTDIR"
  make -C "$KERNEL_DIR" "${KBUILD_OPTS[@]}" mrproper

  TMP_CONFIG=""
  if [ -f "$KERNEL_DIR/.config" ]; then
    echo "[i] Detected kernel .config in source; preserving across mrproper"
    TMP_CONFIG="$(mktemp -p "$OUTDIR" .config.XXXX)"
    if mv "$KERNEL_DIR/.config" "$TMP_CONFIG" 2>/dev/null; then
      echo "[+] Moved source .config -> $TMP_CONFIG"
    else
      echo "[i] mv failed, attempting sudo mv to preserve ownership"
      sudo mv "$KERNEL_DIR/.config" "$TMP_CONFIG"
    fi
    echo "[+] Running source 'make mrproper' (this will remove generated files from source)"
    make -C "$KERNEL_DIR" mrproper
    echo "[+] Installing saved .config into outdir: $OUTDIR/.config"
    mkdir -p "$OUTDIR"

    if cp "$TMP_CONFIG" "$OUTDIR/.config" 2>/dev/null; then
      :
    else
      echo "[i] Failed to copy $TMP_CONFIG as current user; copying with sudo and fixing ownership"
      sudo cp "$TMP_CONFIG" "$OUTDIR/.config"
      sudo chown $(id -u):$(id -g) "$OUTDIR/.config" || true
    fi

    if [ -e "$TMP_CONFIG" ]; then
      sudo chown $(id -u):$(id -g) "$TMP_CONFIG" 2>/dev/null || true
    fi
    echo "[+] Running O=$OUTDIR olddefconfig to populate output tree config"
    make -C "$KERNEL_DIR" "${KBUILD_OPTS[@]}" olddefconfig
  else

    echo "[i] No .config in kernel source; looking for saved config in outdir"
    SAVED_CFG="$(ls -1 "$OUTDIR"/.config* 2>/dev/null | head -n1 || true)"
    if [ -n "$SAVED_CFG" ]; then
      echo "[+] Found saved config in outdir: $SAVED_CFG -> copying to $OUTDIR/.config"
      if cp "$SAVED_CFG" "$OUTDIR/.config" 2>/dev/null; then
        :
      else
        echo "[i] Saved config $SAVED_CFG is not readable; copying with sudo and fixing ownership"
        sudo cp "$SAVED_CFG" "$OUTDIR/.config"
        sudo chown $(id -u):$(id -g) "$OUTDIR/.config" || true
      fi
      TMP_CONFIG="$SAVED_CFG"
      echo "[+] Running O=$OUTDIR olddefconfig to populate output tree config"
      make -C "$KERNEL_DIR" "${KBUILD_OPTS[@]}" olddefconfig
    else
      echo "[i] No saved config found; generating default config in outdir (defconfig)"
      mkdir -p "$OUTDIR"
      make -C "$KERNEL_DIR" "${KBUILD_OPTS[@]}" defconfig
    fi
  fi

  echo "[+] Building kernel (bzImage)"
  set -x
  make -C "$KERNEL_DIR" "${KBUILD_OPTS[@]}" -j"$NUMJOBS" bzImage
  set +x

  if [ -n "${OUTDIR}" ]; then
    SRC_BZ="$OUTDIR/arch/$(uname -m)/boot/bzImage"
    if [ ! -f "$SRC_BZ" ]; then
      # fallback
      SRC_BZ="$OUTDIR/arch/x86/boot/bzImage"
    fi
    if [ -f "$SRC_BZ" ]; then
      echo "[+] Copying bzImage from $SRC_BZ to $KERNEL_DIR/bzImage"
      cp "$SRC_BZ" "$KERNEL_DIR/bzImage"
    else
      echo "[-] Could not find bzImage in outdir: $OUTDIR"
      exit 1
    fi
  fi

    if [ -n "${TMP_CONFIG:-}" ] && [ -f "$TMP_CONFIG" ]; then
      echo "[+] Restoring .config to kernel source"
      if cp "$TMP_CONFIG" "$KERNEL_DIR/.config" 2>/dev/null; then
        :
      else
        echo "[i] Restoring .config requires sudo; performing sudo cp"
        sudo cp "$TMP_CONFIG" "$KERNEL_DIR/.config"
        sudo chown $(id -u):$(id -g) "$KERNEL_DIR/.config" 2>/dev/null || true
      fi
      rm -f "$TMP_CONFIG" || true
    fi
fi

if [ "$DO_DEBOOTSTRAP" -eq 1 ]; then
  if [ ! -x "$BUILD_SCRIPT" ]; then
    echo "[-] Build script not found or not executable: $BUILD_SCRIPT"
    exit 1
  fi
  echo "[+] Running rootfs build: $BUILD_SCRIPT"
  BUILD_ROOT="$BUILD_ROOT" bash "$BUILD_SCRIPT"
fi

echo "[+] build-image complete"
 
