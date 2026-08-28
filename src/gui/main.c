#include "ayui_session.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    bool test_mode = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--test-scene") == 0 || strcmp(argv[i], "--test") == 0) {
            test_mode = true;
        }
    }

    ayui_session_t session;
    if (ayui_session_init(&session, test_mode) < 0) {
        fprintf(stderr, "AWEOS AYUI: Failed to initialize desktop session!\n");
        return 1;
    }

    ayui_session_run(&session);
    ayui_session_close(&session);
    return 0;
}
