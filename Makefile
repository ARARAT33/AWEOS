# AWEOS Build System Makefile
# Canonical interface for AWEOS OS build, testing, and ISO generation.
# IMPORTANT: /linux source directory is strictly read-only and must never be modified.

BUILD_DIR ?= $(PWD)/build
KERNEL_SRC := $(PWD)/linux
KERNEL_BUILD_DIR := $(BUILD_DIR)/linux-x86_64
ISO_PATH := $(BUILD_DIR)/AWEOS-x86_64.iso
DISK_IMG_PATH := $(BUILD_DIR)/AWEOS-x86_64-disk.img

.PHONY: all build verify-linux kernel rootfs initramfs iso disk-image image test test-native test-bios test-uefi test-gui test-ayui test-aweui aweui ayui aosin installer updater wlin wlin-win32 verify-artifacts installer updater wlin clean verify-linux-readonly

all: build

build: verify-linux aweui ayui aosin installer updater wlin wlin-win32 iso disk-image verify-artifacts

verify-linux-readonly:
	@./scripts/verify-linux-readonly.sh

verify-linux: verify-linux-readonly

aweui:
	@mkdir -p $(BUILD_DIR)
	@cargo build --workspace --release
	@set -eu; for binary in \
		aweui-installer aweui-firstboot-setup aweui-settings aweui-control-center \
		aweui-file-manager aweui-terminal aweui-system-monitor aweui-diagnostics \
		aweui-text-editor aweui-calculator; do \
		test -x target/release/$$binary || { echo "ERROR: missing Rust binary target/release/$$binary" >&2; exit 1; }; \
		cp target/release/$$binary $(BUILD_DIR)/$$binary; \
	done
	@test -x target/release/aweui || { echo "ERROR: missing AWEUI compositor binary target/release/aweui" >&2; exit 1; }\n\tcp target/release/aweui $(BUILD_DIR)/aweui

ayui:
	@mkdir -p $(BUILD_DIR)
	@gcc -Isrc/gui -Isrc/apps -Isrc/core -Wall -Wextra -O2 src/gui/*.c src/apps/*.c src/core/*.c -lutil -o $(BUILD_DIR)/aweos-ayui

aosin:
	@mkdir -p $(BUILD_DIR)
	@gcc -Isrc/aosin -Isrc/core -Wall -Wextra -O2 src/core/*.c src/aosin/aosin_core.c src/aosin/main.c -o $(BUILD_DIR)/aosin

installer:
	@mkdir -p $(BUILD_DIR)
	@gcc -Isrc/core -Isrc/installer -Wall -Wextra -O2 src/core/*.c src/installer/installer.c src/installer/main.c -o $(BUILD_DIR)/aweos-installer

updater:
	@mkdir -p $(BUILD_DIR)
	@gcc -Isrc/core -Isrc/updater -Wall -Wextra -O2 src/core/*.c src/updater/updater.c src/updater/main.c -o $(BUILD_DIR)/aweos-update

wlin:
	@mkdir -p $(BUILD_DIR)
	@gcc -Isrc/core -Isrc/wlin -Wall -Wextra -O2 src/core/*.c src/wlin/wlin_core.c src/wlin/main_linux.c -o $(BUILD_DIR)/wlin

wlin-win32:
	@mkdir -p $(BUILD_DIR)
	@if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then \
		x86_64-w64-mingw32-gcc -Isrc/core -Isrc/wlin -Wall -Wextra -O2 src/core/*.c src/wlin/wlin_core.c src/wlin/main_win32.c -o $(BUILD_DIR)/wlin.exe; \
	else \
		echo "Warning: x86_64-w64-mingw32-gcc not found, skipping wlin.exe build"; \
	fi

test-native:
	@mkdir -p $(BUILD_DIR)
	@gcc -Isrc/core -Wall -Wextra -O2 src/core/*.c src/core/tests/test_core.c -o $(BUILD_DIR)/test_core
	@$(BUILD_DIR)/test_core
	@gcc -Isrc/aosin -Isrc/core -Wall -Wextra -O2 src/core/*.c src/aosin/aosin_core.c src/aosin/tests/test_aosin.c -o $(BUILD_DIR)/test_aosin
	@$(BUILD_DIR)/test_aosin

test-aweui:
	@cargo test --workspace

verify-artifacts:
	@set -eu; \
	for artifact in \
		$(ISO_PATH) $(DISK_IMG_PATH) $(BUILD_DIR)/aweos-ayui $(BUILD_DIR)/aweui \
		$(BUILD_DIR)/aosin $(BUILD_DIR)/aweos-installer $(BUILD_DIR)/aweos-update $(BUILD_DIR)/wlin; do \
		test -s "$$artifact" || { echo "ERROR: missing or empty artifact $$artifact" >&2; exit 1; }; \
	done

kernel: verify-linux
	@./scripts/config-kernel.sh $(KERNEL_SRC) $(KERNEL_BUILD_DIR)
	@make -C $(KERNEL_SRC) O=$(KERNEL_BUILD_DIR) -j"$$(nproc)" bzImage
	@test -s $(KERNEL_BUILD_DIR)/arch/x86/boot/bzImage

rootfs: aweui ayui aosin installer updater wlin
	@./scripts/build-rootfs.sh $(BUILD_DIR) 64

initramfs:
	@./scripts/build-initramfs.sh $(BUILD_DIR)

iso: kernel rootfs initramfs
	@./scripts/build-iso.sh $(BUILD_DIR)
	@$(MAKE) verify-linux-readonly

disk-image: rootfs kernel initramfs
	@./scripts/build-disk-image.sh $(BUILD_DIR)

image: iso disk-image

test: test-native test-aweui iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR)

test-bios: iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR) bios

test-uefi: iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR) uefi

test-gui: iso
	@./scripts/run-qemu-tests.sh $(BUILD_DIR) gui

test-ayui: test-gui

gui: qemu-gui

qemu: qemu-gui

qemu-bios: iso
	@qemu-system-x86_64 -machine q35 -m 512M -cdrom $(ISO_PATH) -serial stdio -net nic,model=virtio -net user

qemu-gui: iso
	@qemu-system-x86_64 -machine q35 -m 512M -cdrom $(ISO_PATH) -vga std -serial stdio -net nic,model=virtio -net user

qemu-ayui: qemu-gui

qemu-uefi: iso
	@UEFI=$$(if [ -f /usr/share/ovmf/OVMF.fd ]; then echo /usr/share/ovmf/OVMF.fd; elif [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]; then echo /usr/share/OVMF/OVMF_CODE_4M.fd; else echo /usr/share/OVMF/OVMF_CODE.fd; fi); \
	qemu-system-x86_64 -machine q35 -m 512M -bios "$$UEFI" -cdrom $(ISO_PATH) -vga std -serial stdio -net nic,model=virtio -net user

qemu-gui-uefi: qemu-uefi

clean:
	@rm -rf $(BUILD_DIR)
