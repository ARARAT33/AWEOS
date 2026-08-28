#include "installer.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;
    LOGI("AWEOS Standalone Installer CLI v1.0.0");

    aweos_installer_state_t st;
    if (aweos_installer_init(&st) != AWEOS_OK) {
        fprintf(stderr, "Failed to initialize installer!\n");
        return 1;
    }

    if (aweos_installer_run_cli(&st) != AWEOS_OK) {
        fprintf(stderr, "Installation execution failed!\n");
        return 1;
    }

    printf("AWEOS Installation finished successfully!\n");
    return 0;
}
