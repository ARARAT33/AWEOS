# AWEOS Build System Makefile
# Canonical interface for AWEOS OS build, testing, and ISO generation.
# IMPORTANT: /linux source directory is strictly read-only and must never be modified.

BUILD_DIR ?= $(PWD)/build
KERNEL_SRC := $(PWD)/linux
KERNEL_BUILD_DIR := $(BUILD_DIR)/linux-x86_64
ISO_PATH := $(BUILD_DIR)/AWEOS-x86_64.iso
DISK_IMG_PATH := $(BUILD_DIR)/AWEOS-x86_64-disk.img

.PHONY: all build verify-linux kernel rootfs initramfs iso disk-image image test test-bios test-uefi qemu qemu-bios qemu-uefi clean verify-linux-readonly

all: build

build: verify-linux iso disk-image

verify-linux-readonly:
	@./scripts/verify-linux-readonly.sh

verify-linux: verify-linux-readonly

kernel: verify-linux
	@./scripts/config-kernel.sh $(KERNEL_SRC) $(KERNEL_BUILD_DIR)
	@make -C $(KERNEL_SRC) O=$(KERNEL_BUILD_DIR) -j"$$(nproc)" bzImage
	@test -s $(KERNEL_BUILD_DIR)/arch/x86/boot/bzImage

rootfs:
	@./scripts/build-rootfs.sh $(BUILD_DIR) 64

initramfs:
	@./scripts/build-initramfs.sh $(BUILD_DIR)

iso: kernel rootfs initramfs
	@./scripts/build-iso.sh $(BUILD_DIR)
	@$(MAKE) verify-linux-readonly

disk-image: rootfs kernel initramfs
	@./scripts/build-disk-image.sh $(BUILD_DIR)

image: iso disk-image

test: iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR)

test-bios: iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR) bios

test-uefi: iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR) uefi

qemu: qemu-bios

qemu-bios: iso
	@qemu-system-x86_64 -machine q35 -m 512M -cdrom $(ISO_PATH) -serial stdio -net nic,model=virtio -net user

qemu-uefi: iso
	@UEFI=$$(if [ -f /usr/share/ovmf/OVMF.fd ]; then echo /usr/share/ovmf/OVMF.fd; elif [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]; then echo /usr/share/OVMF/OVMF_CODE_4M.fd; else echo /usr/share/OVMF/OVMF_CODE.fd; fi); \
	qemu-system-x86_64 -machine q35 -m 512M -bios "$$UEFI" -cdrom $(ISO_PATH) -serial stdio -net nic,model=virtio -net user

clean:
	@rm -rf $(BUILD_DIR)
