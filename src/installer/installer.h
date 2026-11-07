#ifndef AWEOS_INSTALLER_H
#define AWEOS_INSTALLER_H

#include "../core/types.h"
#include "../core/storage.h"
#include "../core/transaction.h"

typedef struct {
    aweos_storage_info_t storage;
    int selected_disk_idx;
    int selected_part_idx;
    aweos_install_mode_t mode;
    aweos_boot_mode_t boot_mode;
    bool confirmed_destructive;
    aweos_transaction_t tx;
} aweos_installer_state_t;

int aweos_installer_init(aweos_installer_state_t *st);
/* Select a disk and, for dual boot, an explicit partition. Use -1 for
 * partition_idx only when selecting a full-disk replacement target. */
int aweos_installer_select_target(aweos_installer_state_t *st, int disk_idx, int partition_idx);
int aweos_installer_run_cli(aweos_installer_state_t *st);

#endif /* AWEOS_INSTALLER_H */
