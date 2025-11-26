# Copyright (c) Killian Zabinsky
# All rights reserved.
#
# You may modify this file for personal use only.
# Redistribution in any form is strictly prohibited
# without express written permission from the author.
#
# Modified by: None

SHELL := /bin/bash
BUILD_DIR ?= build
IMAGE_SCRIPT := scripts/build-image.sh
BOOT_SCRIPT := scripts/boot.sh

.PHONY: all image clean

all: image

image:
	@echo "[Makefile] Invoking image build via $(IMAGE_SCRIPT)"
	@bash $(IMAGE_SCRIPT)

clean:
	@echo "[Makefile] Removing build directory: $(BUILD_DIR)"
	@sudo rm -rf "$(BUILD_DIR)" || true

run:
	@echo "[Makefile] Running Vorosium via $(BOOT_SCRIPT)"
	@bash $(BOOT_SCRIPT)