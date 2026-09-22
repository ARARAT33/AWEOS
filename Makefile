# AWEOS Build System
# Canonical interface for the currently implemented AWEOS userland.
# IMPORTANT: /linux is a vendored, strictly read-only kernel tree.

SHELL := /bin/bash
BUILD_DIR ?= $(PWD)/build
KERNEL_SRC := $(PWD)/linux
KERNEL_BUILD_DIR := $(BUILD_DIR)/linux-x86_64
ISO_ROOT := $(BUILD_DIR)/iso-root
ISO_PATH := $(BUILD_DIR)/AWEOS-x86_64.iso

RUST_BINS := aweui aweui-installer aweui-settings aweui-control-center aweui-file-manager              aweui-terminal aweui-system-monitor aweui-diagnostics aweui-text-editor              aweui-calculator aweui-firstboot-setup aweui-user-app-template

.PHONY: all build verify-linux verify-linux-readonly rust-build userland kernel rootfs initramfs iso         test test-rust verify-artifacts clean

all: build

build: verify-linux rust-build kernel rootfs initramfs iso verify-artifacts

verify-linux verify-linux-readonly:
	@./scripts/verify-linux-readonly.sh

rust-build:
	@mkdir -p $(BUILD_DIR)
	@cargo build --workspace --release
	@set -euo pipefail; 	for binary in $(RUST_BINS); do 		test -x "target/release/$$binary" || { echo "ERROR: missing Rust binary target/release/$$binary" >&2; exit 1; }; 		cp "target/release/$$binary" "$(BUILD_DIR)/$$binary"; 	done

userland: rust-build

kernel: verify-linux
	@mkdir -p $(KERNEL_BUILD_DIR)
	@$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_BUILD_DIR) defconfig
	@$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_BUILD_DIR) -j"$$(nproc)" bzImage
	@test -s $(KERNEL_BUILD_DIR)/arch/x86/boot/bzImage

rootfs: rust-build
	@./scripts/build-rootfs.sh $(BUILD_DIR)

initramfs: rootfs
	@./scripts/build-initramfs.sh $(BUILD_DIR)

iso: kernel initramfs
	@./scripts/build-iso.sh $(BUILD_DIR)
	@$(MAKE) verify-linux-readonly

test: verify-linux test-rust
	@$(MAKE) verify-linux-readonly

test-rust:
	@cargo test --workspace

verify-artifacts:
	@set -euo pipefail; 	for artifact in $(BUILD_DIR)/aweui $(BUILD_DIR)/aweui-installer $(BUILD_DIR)/aweui-settings 		$(BUILD_DIR)/aweui-control-center $(BUILD_DIR)/aweui-file-manager $(BUILD_DIR)/aweui-terminal 		$(BUILD_DIR)/aweui-system-monitor $(BUILD_DIR)/aweui-diagnostics $(BUILD_DIR)/aweui-text-editor 		$(BUILD_DIR)/aweui-calculator $(BUILD_DIR)/aweui-firstboot-setup $(BUILD_DIR)/aweui-user-app-template 		$(KERNEL_BUILD_DIR)/arch/x86/boot/bzImage $(BUILD_DIR)/aweos-initramfs.cpio.gz $(ISO_PATH); do 		test -s "$$artifact" || { echo "ERROR: missing or empty artifact $$artifact" >&2; exit 1; }; 	done

clean:
	@rm -rf $(BUILD_DIR)
