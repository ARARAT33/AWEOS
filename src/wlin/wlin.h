#ifndef WLIN_H
#define WLIN_H

#include "../core/types.h"
#include "../core/storage.h"
#include "../core/iso_verify.h"
#include "../core/transaction.h"

typedef struct {
    char iso_path[256];
    aweos_iso_manifest_t manifest;
    aweos_storage_info_t storage;
    aweos_boot_mode_t boot_mode;
    aweos_install_mode_t mode;
    int target_disk_idx;
    bool user_confirmed;
    bool staged_for_reboot;
} wlin_state_t;

int wlin_init(wlin_state_t *st, const char *iso_path);
int wlin_plan(wlin_state_t *st);
int wlin_stage_boot(wlin_state_t *st);
int wlin_execute(wlin_state_t *st);

#endif /* WLIN_H */
