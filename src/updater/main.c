#include "updater.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    LOGI("AWEOS Safe System Updater Utility v1.0.0");
    if (argc < 2) {
        printf("Usage: aweos-update <path_to_aweos.iso>\n");
        return 1;
    }

    const char *iso_path = argv[1];
    aweos_updater_state_t st;
    if (aweos_updater_init(&st, iso_path) != AWEOS_OK) {
        fprintf(stderr, "Failed to initialize update with ISO %s\n", iso_path);
        return 1;
    }

    if (aweos_updater_run(&st) != AWEOS_OK) {
        fprintf(stderr, "Update execution failed!\n");
        return 1;
    }

    printf("AWEOS OS System Update finished successfully!\n");
    return 0;
}
