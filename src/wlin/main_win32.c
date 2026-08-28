#include "wlin.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)
#include <windows.h>
#endif

int main(int argc, char *argv[]) {
    LOGI("WLIN Cross-OS Installation Tool v1.0.0 (Windows Native)");

    const char *iso_path = (argc >= 2) ? argv[1] : "AWEOS-x86_64.iso";
    wlin_state_t st;
    if (wlin_init(&st, iso_path) != AWEOS_OK) {
        fprintf(stderr, "WLIN Win32 initialization failed for %s\n", iso_path);
        return 1;
    }

    if (wlin_execute(&st) != AWEOS_OK) {
        fprintf(stderr, "WLIN Win32 execution failed!\n");
        return 1;
    }

    printf("WLIN Win32 installation & staging completed successfully!\n");
    return 0;
}
