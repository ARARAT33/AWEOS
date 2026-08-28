#include "wm.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    printf("AWEOS GRAPHICS INITIALIZING\n");
    printf("AWEOS GRAPHICS READY\n");
    printf("AWEOS INPUT INITIALIZING\n");
    printf("AWEOS INPUT READY\n");

    aweos_wm_t wm;
    if (aweos_wm_init(&wm) < 0) {
        fprintf(stderr, "AWEOS Desktop: Failed to initialize window manager/graphics!\n");
        return 1;
    }

    aweos_wm_run(&wm);
    aweos_wm_close(&wm);
    return 0;
}
