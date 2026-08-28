#include "wlin.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    LOGI("WLIN Cross-OS Installation Tool v1.0.0 (Linux)");
    if (argc < 2) {
        printf("Usage: wlin <path_to_aweos.iso>\n");
        return 1;
    }

    const char *iso_path = argv[1];
    wlin_state_t st;
    if (wlin_init(&st, iso_path) != AWEOS_OK) {
        fprintf(stderr, "WLIN initialization failed for %s\n", iso_path);
        return 1;
    }

    if (wlin_execute(&st) != AWEOS_OK) {
        fprintf(stderr, "WLIN installation execution failed!\n");
        return 1;
    }

    printf("WLIN installation and boot staging completed successfully!\n");
    return 0;
}
