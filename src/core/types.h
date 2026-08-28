#ifndef AWEOS_TYPES_H
#define AWEOS_TYPES_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define AWEOS_VERSION "1.0.0"
#define AWEOS_ARCH "x86_64"

typedef enum {
    AWEOS_OK = 0,
    AWEOS_ERR_GENERIC = -1,
    AWEOS_ERR_INVALID_PARAM = -2,
    AWEOS_ERR_NO_MEM = -3,
    AWEOS_ERR_IO = -4,
    AWEOS_ERR_NOT_FOUND = -5,
    AWEOS_ERR_PERMISSION = -6,
    AWEOS_ERR_VERIFY = -7,
    AWEOS_ERR_SPACE = -8,
    AWEOS_ERR_STAGE = -9,
    AWEOS_ERR_TRANSACTION = -10
} aweos_error_t;

typedef enum {
    BOOT_MODE_UNKNOWN = 0,
    BOOT_MODE_BIOS,
    BOOT_MODE_UEFI
} aweos_boot_mode_t;

typedef enum {
    INSTALL_MODE_DUAL_BOOT = 0,
    INSTALL_MODE_REPLACE_DISK
} aweos_install_mode_t;

typedef enum {
    TX_STATE_PLAN = 0,
    TX_STATE_VALIDATE,
    TX_STATE_PREPARE,
    TX_STATE_PRESERVE,
    TX_STATE_EXECUTE,
    TX_STATE_BOOTCFG,
    TX_STATE_VERIFY,
    TX_STATE_COMMIT,
    TX_STATE_ABORTED,
    TX_STATE_FAILED
} aweos_tx_state_t;

#endif /* AWEOS_TYPES_H */
