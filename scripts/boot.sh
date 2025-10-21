#!/bin/bash

# Copyright (c) Killian Zabinsky
# All rights reserved.
#
# You may modify this file for personal use only.
# Redistribution in any form is strictly prohibited
# without express written permission from the author.
#
# Modified by: None

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KERNEL="$PROJ_ROOT/kernel/bzImage"
DEBIAN_IMG="$PROJ_ROOT/build/kernel/debian.img"
DEBIAN_IMG_ALT="$PROJ_ROOT/build/debian.img"
VOROSIUM_IMG="$PROJ_ROOT/build/kernel/vorosium-rootfs.img"
VOROSIUM_IMG_ALT="$PROJ_ROOT/build/vorosium-rootfs.img"
LIVE_ROOT="$PROJ_ROOT/build/vorosium-rootfs"
INIT_FILE="$PROJ_ROOT/ramdisk/init"
BUILDER_SCRIPT="$PROJ_ROOT/scripts/debootstrap-debian.sh"
LOG_FILE="$PROJ_ROOT/build/boot.log"

MEMORY="1024"
NAME="Vorosium - Kernel"
CONSOLE="console=ttyS0 net.ifnames=0 biosdevname=0"
ROOT="/dev/vda"
INIT="/sbin/init"
KVM="-enable-kvm"

# Default to Wayland, devs can force -nogui
GRAPHICS=""
USE_GL="0"
USE_SDL="0"

show_help() {
  echo "Vorosium Boot Options:"
  echo "  -nogui     Run in text-only mode (no QEMU window)"
  echo "  -gui       Run with QEMU graphical window (default)"
  echo "  -help      Show this help message"
  exit 0
}

print_debug() {
  echo -e "\033[1;31m[DEBUG]\033[0m $1" | tee -a "$LOG_FILE" >/dev/null
}

install_dependencies() {
  print_debug "Checking and installing required dependencies."
  if ! dpkg -l | grep -q python3-tk; then
    print_debug "Installing python3-tk..."
    sudo apt-get update && sudo apt-get install -y python3-tk
  fi
}

# args
DEBUG=""
DO_BUILD=""
for arg in "$@"; do
  case $arg in
    -nogui)
      GRAPHICS="-nographic"
      ;;
    -gui)
      GRAPHICS=""
      ;;
    -help|--help)
      show_help
      ;;
    -debug)
      DEBUG="debug"
      print_debug "Debug mode enabled."
      ;;
    -gl)
      USE_GL="1"
      ;;
    -sdl)
      USE_SDL="1"
      ;;
    -build)
      DO_BUILD="1"
      ;;
    -control)
      print_debug "Launching Control Window."
      install_dependencies
      python3 "$PROJ_ROOT/kernel/control_window.py" || python3 "$PROJ_ROOT/control_window.py"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Use -help for available options."
      exit 1
      ;;
  esac
done

# check build directory's existence
if [ ! -d "$PROJ_ROOT/build" ]; then
  print_debug "Creating project build directory."
  mkdir -p "$PROJ_ROOT/build"
fi

if [ ! -d "$LIVE_ROOT" ]; then
  print_debug "Creating vorosium-rootfs directory under build/."
  mkdir -p "$LIVE_ROOT"
fi

# Check init file
if [ ! -f "$INIT_FILE" ]; then
  print_debug "Init file not found. Creating a placeholder init file."
  mkdir -p "$PROJ_ROOT/ramdisk"
  echo -e "#!/bin/sh\necho 'Init script placeholder'" > "$INIT_FILE"
  chmod +x "$INIT_FILE"
fi

# Verify the init file
if [ ! -f "$LIVE_ROOT/init" ]; then
  print_debug "No working init file found at $LIVE_ROOT/init. Creating a placeholder init file."
  echo -e "#!/bin/sh\necho 'Placeholder init script'\nsleep 5" > "$LIVE_ROOT/init"
  chmod +x "$LIVE_ROOT/init"
fi

# Check kernel file
if [ ! -f "$KERNEL" ]; then
  print_debug "Kernel file not found at $KERNEL. Creating a placeholder to avoid immediate failure." 
  mkdir -p "$PROJ_ROOT/kernel"
  echo "Placeholder for bzImage" > "$KERNEL" || true
fi

if ! file "$KERNEL" | grep -q "Linux kernel"; then
  print_debug "Invalid or non-kernel file at $KERNEL. Please rebuild the kernel if you want to boot an actual kernel."
  # do not exit here so user can still run with initramfs-only
fi

APPEND="$CONSOLE root=$ROOT rw init=$INIT $DEBUG"

# Image Fallback Logic
DISK_IMG=""
if [ -f "$DEBIAN_IMG" ]; then
  DISK_IMG="$DEBIAN_IMG"
elif [ -f "$DEBIAN_IMG_ALT" ]; then
  DISK_IMG="$DEBIAN_IMG_ALT"
elif [ -f "$PROJ_ROOT/kernel/build/debian.img" ]; then
  DISK_IMG="$PROJ_ROOT/kernel/build/debian.img"
elif [ -f "$PROJ_ROOT/kernel/debian.img" ]; then
  DISK_IMG="$PROJ_ROOT/kernel/debian.img"
elif [ -f "$VOROSIUM_IMG" ]; then
  DISK_IMG="$VOROSIUM_IMG"
elif [ -f "$VOROSIUM_IMG_ALT" ]; then
  DISK_IMG="$VOROSIUM_IMG_ALT"
fi

if [ -n "$DO_BUILD" ]; then
  print_debug "-build specified: running $BUILDER_SCRIPT"
  if [ -x "$BUILDER_SCRIPT" ] || [ -f "$BUILDER_SCRIPT" ]; then
    bash "$BUILDER_SCRIPT" || { echo "Builder failed"; exit 1; }
    DISK_IMG="$PROJ_ROOT/build/kernel/debian.img"
  else
    echo "Builder script not found at $BUILDER_SCRIPT"; exit 1
  fi
fi

if [ -z "$DISK_IMG" ]; then
  print_debug "No disk image found. Expected $DEBIAN_IMG or $VOROSIUM_IMG under build/."
  if [ -f "$BUILDER_SCRIPT" ]; then
    print_debug "Attempting to build Debian image automatically..."
    bash "$BUILDER_SCRIPT" || { echo "Auto-build failed"; exit 1; }
    DISK_IMG="$PROJ_ROOT/build/kernel/debian.img"
  else
    print_debug "Run: ./scripts/debootstrap-debian.sh to create a Debian rootfs image."
    exit 1
  fi
fi

print_debug "Using disk image: $DISK_IMG"

# Auto-networking and serial
NET_OPTS=("-device" "virtio-net-pci,netdev=n0,mac=52:54:00:12:34:56" "-netdev" "user,id=n0,hostfwd=tcp::2222-:22")

# Video and input devices for Wayland
if [ "$USE_GL" = "1" ]; then
  VIDEO_OPTS=("-device" "virtio-vga-gl" "-display" "gtk,gl=on")
else
  VIDEO_OPTS=("-device" "virtio-gpu-pci" "-display" "gtk")
fi
if [ "$USE_SDL" = "1" ]; then
  if [ "$USE_GL" = "1" ]; then
    VIDEO_OPTS=("-device" "virtio-vga-gl" "-display" "sdl,gl=on")
  else
    VIDEO_OPTS=("-device" "virtio-gpu-pci" "-display" "sdl")
  fi
fi
INPUT_OPTS=(
  "-device" "virtio-keyboard-pci"
  "-device" "virtio-mouse-pci"
)

# Make QEMU command
QEMU_CMD=(
  "qemu-system-x86_64"
  "-name" "$NAME"
  "-vga" "none"
  "-kernel" "$KERNEL"
  "-append" "$APPEND"
  "-m" "$MEMORY"
  "$KVM"
  $GRAPHICS
  "-serial" "mon:stdio"
  "-device" "virtio-blk-pci,drive=vda"
  "-drive" "if=none,id=vda,file=$DISK_IMG,format=raw"
  "-cpu" "host"
  "-smp" "2"
  "${NET_OPTS[@]}"
  "${VIDEO_OPTS[@]}"
  "${INPUT_OPTS[@]}"
)

echo "Executing QEMU Command: ${QEMU_CMD[@]}"

# Cleaning
cleanup() {
  print_debug "Cleaning up temporary files and directories."
  if [ -d "$LIVE_ROOT" ]; then
    rm -rf "$LIVE_ROOT"
    print_debug "Removed live root directory: $LIVE_ROOT"
  fi
}

trap cleanup EXIT

# Run QEMU
exec "${QEMU_CMD[@]}"
