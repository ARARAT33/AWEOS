# AWEOS Build System
# Canonical interface for the currently implemented AWEOS userland.
# IMPORTANT: /linux is a vendored, strictly read-only kernel tree.

SHELL := /bin/bash
BUILD_DIR ?= $(PWD)/build
KERNEL_SRC := $(PWD)/linux
KERNEL_BUILD_DIR := $(BUILD_DIR)/linux-x86_64
ISO_PATH := $(BUILD_DIR)/AWEOS-x86_64.iso
ROOTFS_IMG := $(BUILD_DIR)/rootfs.img
ROOTFS_DIR := $(BUILD_DIR)/rootfs
INITRAMFS := $(BUILD_DIR)/aweos-initramfs.cpio.gz
LIMINE_TOOL ?= $(shell command -v limine 2>/dev/null || true)

RUST_BINS := aweui aweui-installer aweui-settings aweui-control-center aweui-file-manager \
             aweui-terminal aweui-system-monitor aweui-diagnostics aweui-text-editor \
             aweui-calculator aweui-firstboot-setup aweui-user-app-template
SHELL_SCRIPTS := $(shell find scripts -maxdepth 1 -type f -name '*.sh' -print | sort)

.PHONY: all build verify-linux verify-linux-readonly rust-build userland kernel rootfs \
        initramfs finalize-rootfs iso disk-image image check test test-rust test-shell test-qemu \
        validate-rootfs verify-artifacts clean

all: build

build: verify-linux rust-build kernel rootfs initramfs finalize-rootfs iso disk-image verify-artifacts

verify-linux verify-linux-readonly:
	@./scripts/verify-linux-readonly.sh

rust-build:
	@mkdir -p $(BUILD_DIR)
	@cargo build --workspace --release
	@set -euo pipefail; \
	for binary in $(RUST_BINS); do \
		test -x "target/release/$$binary" || { echo "ERROR: missing Rust binary target/release/$$binary" >&2; exit 1; }; \
		cp "target/release/$$binary" "$(BUILD_DIR)/$$binary"; \
	done

userland: rust-build

kernel: verify-linux
	@mkdir -p $(KERNEL_BUILD_DIR)
	@./scripts/config-kernel.sh $(KERNEL_SRC) $(KERNEL_BUILD_DIR)
	@$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_BUILD_DIR) -j"$$(nproc)" bzImage
	@test -s $(KERNEL_BUILD_DIR)/arch/x86/boot/bzImage

rootfs: rust-build
	@AWEOS_DESKTOP=${AWEOS_DESKTOP:-ayui} ./scripts/build-rootfs.sh $(BUILD_DIR)
	@./scripts/validate-rootfs-layout.sh $(BUILD_DIR)

validate-rootfs:
	@./scripts/validate-rootfs-layout.sh $(BUILD_DIR)

initramfs: rootfs
	@./scripts/build-initramfs.sh $(BUILD_DIR)

finalize-rootfs: initramfs
	@set -euo pipefail; \
	test -d "$(ROOTFS_DIR)"; \
	mkdir -p "$(ROOTFS_DIR)/boot"; \
	cp "$(KERNEL_BUILD_DIR)/arch/x86/boot/bzImage" "$(ROOTFS_DIR)/boot/bzImage"; \
	cp "$(INITRAMFS)" "$(ROOTFS_DIR)/boot/aweos-initramfs.cpio.gz"; \
	cp Bootloader/x86_64/limine-bios.sys "$(ROOTFS_DIR)/boot/limine-bios.sys"; \
	cp Bootloader/x86_64/BOOTX64.EFI "$(ROOTFS_DIR)/boot/BOOTX64.EFI"; \
	test -n "$(LIMINE_TOOL)" || { echo "ERROR: limine host utility is required; set LIMINE_TOOL=/path/to/limine or install it in PATH." >&2; exit 1; }; \
	cp "$$(readlink -f "$(LIMINE_TOOL)")" "$(ROOTFS_DIR)/usr/bin/limine"; \
	chmod 0755 "$(ROOTFS_DIR)/usr/bin/limine"; \
	rm -f "$(ROOTFS_IMG)"; \
	dd if=/dev/zero of="$(ROOTFS_IMG)" bs=1M count=128 status=none; \
	mke2fs -t ext4 -F -d "$(ROOTFS_DIR)" "$(ROOTFS_IMG)" >/dev/null; \
	test -s "$(ROOTFS_IMG)"

iso: kernel finalize-rootfs
	@./scripts/build-iso.sh $(BUILD_DIR)
	@$(MAKE) verify-linux-readonly

disk-image: kernel finalize-rootfs
	@./scripts/build-disk-image.sh $(BUILD_DIR)

image: iso disk-image

check: verify-linux test-shell
	@cargo fmt --all -- --check
	@cargo check --workspace --all-targets

test: verify-linux test-shell test-rust

test-rust:
	@cargo test --workspace

test-shell:
	@set -euo pipefail; \
	for script in $(SHELL_SCRIPTS); do \
		bash -n "$$script"; \
	done

test-qemu: iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR)

verify-artifacts:
	@set -euo pipefail; \
	for artifact in \
		$(BUILD_DIR)/aweui $(BUILD_DIR)/aweui-installer $(BUILD_DIR)/aweui-settings \
		$(BUILD_DIR)/aweui-control-center $(BUILD_DIR)/aweui-file-manager $(BUILD_DIR)/aweui-terminal \
		$(BUILD_DIR)/aweui-system-monitor $(BUILD_DIR)/aweui-diagnostics $(BUILD_DIR)/aweui-text-editor \
		$(BUILD_DIR)/aweui-calculator $(BUILD_DIR)/aweui-firstboot-setup $(BUILD_DIR)/aweui-user-app-template \
		$(KERNEL_BUILD_DIR)/arch/x86/boot/bzImage $(INITRAMFS) $(ROOTFS_IMG) \
		$(ISO_PATH) $(BUILD_DIR)/AWEOS-x86_64-disk.img; do \
		test -s "$$artifact" || { echo "ERROR: missing or empty artifact $$artifact" >&2; exit 1; }; \
	done

clean:
	@rm -rf $(BUILD_DIR)
