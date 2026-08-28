#ifndef AWEOS_UPDATER_H
#define AWEOS_UPDATER_H

#include "../core/types.h"
#include "../core/iso_verify.h"
#include "../core/transaction.h"

typedef struct {
    char current_version[32];
    char candidate_version[32];
    char iso_path[256];
    bool preserve_user_data;
    bool ready_to_update;
} aweos_updater_state_t;

int aweos_updater_init(aweos_updater_state_t *st, const char *iso_path);
int aweos_updater_run(aweos_updater_state_t *st);

#endif /* AWEOS_UPDATER_H */
