#include "aosin_spec.h"

#include <stdio.h>
#include <string.h>

static void print_err(const char *cmd, int rc) {
    fprintf(stderr, "aosin: %s failed with error %d\n", cmd, rc);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr,
            "usage: aosin <command> ...\n"
            "  aosin create <out.asp> <type> <name> <version> <payload_dir>\n"
            "  aosin verify <pkg>\n"
            "  aosin info <pkg>\n"
            "  aosin install <pkg> <root>\n"
            "  aosin remove <name> <root>\n");
        return 2;
    }
    const char *cmd = argv[1];

    if (strcmp(cmd, "create") == 0) {
        if (argc < 7) { fprintf(stderr, "create needs out, type, name, version, payload_dir\n"); return 2; }
        aosin_pkg_type_t type = (aosin_pkg_type_t)(argv[3][0] - '0');
        int rc = aosin_pkg_create(argv[2], type, argv[4], argv[5], argv[6]);
        if (rc != AWEOS_OK) { print_err("create", rc); return 1; }
        printf("created %s\n", argv[2]);
        return 0;
    }
    if (strcmp(cmd, "verify") == 0) {
        if (argc < 3) return 2;
        int rc = aosin_pkg_verify(argv[2]);
        if (rc != AWEOS_OK) { print_err("verify", rc); return 1; }
        printf("OK\n");
        return 0;
    }
    if (strcmp(cmd, "info") == 0) {
        if (argc < 3) return 2;
        aosin_pkg_info_t info;
        int rc = aosin_pkg_inspect(argv[2], &info);
        if (rc != AWEOS_OK) { print_err("inspect", rc); return 1; }
        printf("package: %s\nversion: %s\nfiles: %u\npayload: %llu bytes\nsha256: %s\n",
               info.header.name, info.header.version, info.header.file_count,
               (unsigned long long)info.header.payload_size, info.header.sha256);
        return 0;
    }
    if (strcmp(cmd, "install") == 0) {
        if (argc < 4) return 2;
        int rc = aosin_pkg_install(argv[2], argv[3]);
        if (rc != AWEOS_OK) { print_err("install", rc); return 1; }
        printf("installed\n");
        return 0;
    }
    if (strcmp(cmd, "remove") == 0) {
        if (argc < 4) return 2;
        int rc = aosin_pkg_remove(argv[2], argv[3]);
        if (rc != AWEOS_OK) { print_err("remove", rc); return 1; }
        printf("removed\n");
        return 0;
    }
    fprintf(stderr, "unknown command: %s\n", cmd);
    return 2;
}
