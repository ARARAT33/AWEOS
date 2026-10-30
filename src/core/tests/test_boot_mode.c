#include "../storage.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/vfs.h>
#include <linux/magic.h>

int main(void) {
    struct statfs sysfs;
    assert(statfs("/sys", &sysfs) == 0);
    assert((unsigned long)sysfs.f_type == (unsigned long)SYSFS_MAGIC);

    struct stat efi;
    int efi_result = stat("/sys/firmware/efi", &efi);
    int efi_errno = errno;
    assert(efi_result == 0 || efi_errno == ENOENT);

    aweos_boot_mode_t mode = BOOT_MODE_UNKNOWN;
    assert(aweos_detect_boot_mode(&mode) == AWEOS_OK);
    if (efi_result == 0) {
        assert(S_ISDIR(efi.st_mode));
        assert(mode == BOOT_MODE_UEFI);
    } else {
        assert(mode == BOOT_MODE_BIOS);
    }

    puts("PASS: boot-mode detection requires mounted sysfs and agrees with the EFI firmware directory.");
    return 0;
}
