#include "aosin_spec.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_usage(void) {
    printf("AOSIN Package Management Tool v1.0.0 (x86_64)\n");
    printf("Usage:\n");
    printf("  aosin info <package_file>\n");
    printf("  aosin install <package_file>\n");
    printf("  aosin remove <package_name>\n");
    printf("  aosin create <output_file> <asp|asa|aosin> <name> <version>\n");
    printf("  aosin verify <package_file>\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    const char *cmd = argv[1];
    if (strcmp(cmd, "info") == 0 && argc >= 3) {
        aosin_pkg_info_t info;
        if (aosin_pkg_inspect(argv[2], &info) == AWEOS_OK) {
            printf("Package Name: %s\n", info.header.name);
            printf("Version:      %s\n", info.header.version);
            printf("Architecture: %s\n", info.header.arch);
            printf("Package Type: %d\n", info.header.pkg_type);
            printf("Description:  %s\n", info.description);
            printf("Entrypoint:   %s\n", info.app_entrypoint);
            return 0;
        }
        return 1;
    } else if (strcmp(cmd, "install") == 0 && argc >= 3) {
        return aosin_pkg_install(argv[2], NULL) == AWEOS_OK ? 0 : 1;
    } else if (strcmp(cmd, "remove") == 0 && argc >= 3) {
        return aosin_pkg_remove(argv[2], NULL) == AWEOS_OK ? 0 : 1;
    } else if (strcmp(cmd, "verify") == 0 && argc >= 3) {
        return aosin_pkg_verify(argv[2]) == AWEOS_OK ? 0 : 1;
    } else if (strcmp(cmd, "create") == 0 && argc >= 6) {
        aosin_pkg_type_t type = PKG_TYPE_ASP;
        if (strcmp(argv[3], "asa") == 0) type = PKG_TYPE_ASA;
        if (strcmp(argv[3], "aosin") == 0) type = PKG_TYPE_AOSIN;
        return aosin_pkg_create(argv[2], type, argv[4], argv[5], NULL) == AWEOS_OK ? 0 : 1;
    }

    print_usage();
    return 1;
}
