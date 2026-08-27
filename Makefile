# AWEOS Build System Makefile
# Canonical interface for AWEOS OS build, testing, and ISO generation.
# IMPORTANT: /linux source directory is strictly read-only and must never be modified.

BUILD_DIR ?= $(PWD)/build
KERNEL_SRC := $(PWD)/linux
KERNEL_BUILD_DIR := $(BUILD_DIR)/linux-x86_64
ISO_PATH := $(BUILD_DIR)/AWEOS-x86_64.iso

.PHONY: all build kernel initramfs iso test qemu-bios qemu-uefi clean verify-linux

all: build

build: verify-linux iso

verify-linux:
	@test -f $(KERNEL_SRC)/Makefile
	@test -z "$$(git status --porcelain -- $(KERNEL_SRC))" || (echo "ERROR: /linux source directory modified!" && exit 1)

kernel: verify-linux
	@mkdir -p $(KERNEL_BUILD_DIR)
	@if [ ! -f $(KERNEL_BUILD_DIR)/.config ]; then \
		make -C $(KERNEL_SRC) O=$(KERNEL_BUILD_DIR) x86_64_defconfig; \
		$(KERNEL_SRC)/scripts/config --file $(KERNEL_BUILD_DIR)/.config \
			--disable CONFIG_DEBUG_INFO \
			--disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
			--disable CONFIG_DEBUG_INFO_DWARF4 \
			--disable CONFIG_DEBUG_INFO_DWARF5 \
			--disable CONFIG_DEBUG_INFO_BTF \
			--enable CONFIG_DEVTMPFS \
			--enable CONFIG_DEVTMPFS_MOUNT \
			--enable CONFIG_SERIAL_8250 \
			--enable CONFIG_SERIAL_8250_CONSOLE \
			--enable CONFIG_BLK_DEV_INITRD \
			--enable CONFIG_RD_GZIP; \
		make -C $(KERNEL_SRC) O=$(KERNEL_BUILD_DIR) olddefconfig; \
	fi
	@make -C $(KERNEL_SRC) O=$(KERNEL_BUILD_DIR) -j"$$(nproc)" bzImage
	@test -s $(KERNEL_BUILD_DIR)/arch/x86/boot/bzImage

initramfs:
	@./scripts/build-initramfs.sh $(BUILD_DIR)

iso: kernel initramfs
	@./scripts/build-iso.sh $(BUILD_DIR)
	@$(MAKE) verify-linux

test: iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR)

qemu-bios: iso
	@qemu-system-x86_64 -machine q35 -m 512M -cdrom $(ISO_PATH) -serial stdio

qemu-uefi: iso
	@UEFI=$$(if [ -f /usr/share/ovmf/OVMF.fd ]; then echo /usr/share/ovmf/OVMF.fd; elif [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]; then echo /usr/share/OVMF/OVMF_CODE_4M.fd; else echo /usr/share/OVMF/OVMF_CODE.fd; fi); \
	qemu-system-x86_64 -machine q35 -m 512M -bios "$$UEFI" -cdrom $(ISO_PATH) -serial stdio

clean:
	@rm -rf $(BUILD_DIR)
