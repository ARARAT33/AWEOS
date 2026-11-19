#include "aosin_spec.h"

#include "../core/logging.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define STAGING_SUFFIX ".stage"
#define META_DIR "var/lib/awepkg"
#define APPS_DIR "opt/aweos-pkg"

static int mkdir_p(const char *path) {
    if (!path || !path[0]) return AWEOS_ERR_INVALID_PARAM;
    char copy[512];
    size_t len = strlen(path);
    if (len >= sizeof(copy)) return AWEOS_ERR_INVALID_PARAM;
    memcpy(copy, path, len + 1);
    for (char *p = copy + 1; *p; ++p) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(copy, 0755) != 0 && errno != EEXIST) return AWEOS_ERR_IO;
            *p = '/';
        }
    }
    if (mkdir(copy, 0755) != 0 && errno != EEXIST) return AWEOS_ERR_IO;
    return AWEOS_OK;
}

/* Package names are limited to A-Z, a-z, 0-9, dash, dot, underscore;
 * they never contain path separators. */
static int is_valid_pkg_name(const char *name) {
    if (!name || !name[0]) return 0;
    size_t len = strlen(name);
    if (len >= 64) return 0;
    for (size_t i = 0; i < len; ++i) {
        char c = name[i];
        int ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                 (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_';
        if (!ok) return 0;
    }
    return 1;
}

/* Entry paths must be relative, must not escape the extraction root, must not
 * contain a trailing or doubled slash, and may only use a conservative safe
 * character set. This is what keeps install() from writing outside its root. */
static int is_valid_entry_path(const char *path) {
    if (!path || !path[0]) return 0;
    size_t len = strlen(path);
    if (len >= AOSIN_MAX_ENTRY_PATH) return 0;
    if (path[0] == '/') return 0;
    if (strstr(path, "..") != NULL) return 0;
    if (strstr(path, "//") != NULL) return 0;
    if (path[len - 1] == '/') return 0;
    for (size_t i = 0; i < len; ++i) {
        char c = path[i];
        int ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                 (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' ||
                 c == '/';
        if (!ok) return 0;
    }
    /* A slash-dot component would normalize away or hide a directory part,
     * so reject it explicitly. */
    if (strstr(path, "/.") != NULL) return 0;
    return 1;
}
