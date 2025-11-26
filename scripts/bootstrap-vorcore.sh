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
BUILD_DIR="$BUILD_ROOT"
IMG_PATH="$BUILD_DIR/vorosium.img"
VOR_DIR="$ROOT_DIR/VORCORE"
ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"

VER_INFO_DIR="$ROOT_DIR/versioninfo.json"

REL_VERSION="${REL_VERSION:-unknown}"
REL_TYPE="${REL_TYPE:-unknown}"
REL_CODENAME="${REL_CODENAME:-unknown}"
VER_COMMENT="VorosiumOS"

# Retrieve version info
if [ -r "$VER_INFO_DIR" ]; then
    if command -v jq >/dev/null 2>&1; then
        v=$(jq -r '.version // empty' "$VER_INFO_DIR" 2>/dev/null || true)
        t=$(jq -r '.releasetype // empty' "$VER_INFO_DIR" 2>/dev/null || true)
        c=$(jq -r '.codename // empty' "$VER_INFO_DIR" 2>/dev/null || true)

        REL_VERSION=${v:-$REL_VERSION}
        REL_TYPE=${t:-$REL_TYPE}
        REL_CODENAME=${c:-$REL_CODENAME}

        VER_COMMENT="VorosiumOS $REL_VERSION $REL_TYPE $REL_CODENAME"
    else
        echo -e "\033[31m[FATAL] jq not found; Please install based on your Distro (e.g. sudo apt install jq)\033[0m" >&2
        echo -e "\033[31mAborting...\033[0m" >&2
        exit 1
    fi
else
    echo -e "[WARN]\033[33m[FATAL] Version info file not found - $VER_INFO_DIR\033[0m" >&2
    echo -e "\033[33mAborting...\033[0m" >&2
    exit 1
fi

echo "[+] Using ROOT_DIR=$ROOT_DIR"
echo "[+] Target image: $IMG_PATH ${IMAGE_SIZE_MB:-Unknown} Size"

# Systemd service for default configs

# Mount Image
IMG="$IMG_PATH"
MNT=$(mktemp -d)
sudo mount -o loop "$IMG" "$MNT"
sudo mkdir -p "$MNT/etc"

# Set motd
sudo tee "$MNT/etc/motd" >/dev/null <<EOF
VorosiumOS - $VER_COMMENT
Made for creators. Not for shareholders.
EOF

# Systemd service for VORDEFCONFIGS
sudo tee "$MNT/etc/systemd/system/vordefconfigs.service" >/dev/null <<'EOF'
[Unit]
Description=Default Configs for Vorosium
After=systemd-user-sessions.service seatd.service dbus.service
Wants=seatd.service dbus.service

[Service]
Type=simple
User=vorosium
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WAYLAND_DISPLAY=wayland-0
ExecStart=/usr/local/bin/vordefconfigs
Restart=on-failure
RestartSec=2
TimeoutStopSec=5

[Install]
WantedBy=graphical.target
EOF

# Systemd service for VORSEC
sudo tee "$MNT/etc/systemd/system/vorsec.service" >/dev/null <<'EOF'
[Unit]
Description=Vorosium Security Service
After=systemd-user-sessions.service seatd.service dbus.service
Wants=seatd.service dbus.service

[Service]
Type=simple
User=vorosium
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WAYLAND_DISPLAY=wayland-0
ExecStart=/usr/local/bin/vorsec
Restart=on-failure
RestartSec=2
TimeoutStopSec=5

[Install]
WantedBy=graphical.target
EOF

# Systemd service for Vorscreen
sudo tee "$MNT/etc/systemd/system/vorscreen.service" >/dev/null <<'EOF'
[Unit]
Description=Vorosium Screen Service
After=systemd-user-sessions.service seatd.service dbus.service
Wants=seatd.service dbus.service

[Service]
Type=simple
User=vorosium
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WAYLAND_DISPLAY=wayland-0
ExecStart=/usr/local/bin/vorscreen
Restart=on-failure
RestartSec=2
TimeoutStopSec=5

[Install]
WantedBy=graphical.target
EOF

# Enable Services
sudo chroot "$MNT" /bin/bash -c " 
    systemctl enable vordefconfigs.service
    systemctl enable vorsec.service
    systemctl enable vorscreen.service" || {
    echo "[-] Failed to enable services. Aborting."
    exit 1
}

echo "[+] Services Created with no errors."
echo "[+] Moving Binaries..."

sudo cp "$VOR_DIR/requiredpkgs/vordefconfigs" "$MNT/usr/local/bin/vordefconfigs" || {
    echo "[-] Failed to copy vordefconfigs binary. Aborting."
    exit 1
}
sudo cp "$VOR_DIR/requiredpkgs/vorsec" "$MNT/usr/local/bin/vorsec" || {
    echo "[-] Failed to copy vorsec binary. Aborting."
    exit 1
}
sudo cp "$VOR_DIR/requiredpkgs/vorscreen" "$MNT/usr/local/bin/vorscreen" || {
    echo "[-] Failed to copy vorscreen binary. Aborting."
    exit 1
}

echo "[+] Binaries Copied Successfully with no errors."
echo "[+] Bootstrap Vorcore Completed Successfully."

# Unmount Image
sudo umount "$MNT"
rmdir "$MNT"









