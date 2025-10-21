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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Searching for files >50M under: $REPO_ROOT (excluding $REPO_ROOT/build)"

if [ "$(id -u)" -eq 0 ]; then
	find "$REPO_ROOT" -path "$REPO_ROOT/build" -prune -o -type f -size +50M -print
else
	sudo find "$REPO_ROOT" -path "$REPO_ROOT/build" -prune -o -type f -size +50M -print
fi
