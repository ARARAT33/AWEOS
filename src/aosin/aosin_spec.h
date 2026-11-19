#ifndef AOSIN_SPEC_H
#define AOSIN_SPEC_H

#include "../core/types.h"

#define AOSIN_MAGIC 0x4E49534F /* "OSIN" in Little-Endian */

/*
 * AOSIN package format v2.
 *
 * Layout: aosin_header_t, then file_count aosin_entry_t records, then the
 * raw bytes of each payload file back to back. The header SHA-256 covers
 * exactly payload_size payload bytes and is re-verified on every inspect,
 * verify and install call. Legacy v1 packages (dummy payload, empty-input
 * hash, no entry table) are rejected fail-closed.
 */

#define AOSIN_FORMAT_VER 2U
#define AOSIN_MAX_ENTRIES 512U
#define AOSIN_MAX_ENTRY_PATH 192U
#define AOSIN_MAX_FILE_SIZE (64ULL * 1024ULL * 1024ULL)
#define AOSIN_MAX_TOTAL_SIZE (512ULL * 1024ULL * 1024ULL)
#define AOSIN_MAX_NAME_LEN 32U

typedef enum {
    PKG_TYPE_ASP = 1,
    PKG_TYPE_ASA = 2,
    PKG_TYPE_AOSIN = 3
} aosin_pkg_type_t;

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint16_t format_ver;
    uint16_t pkg_type;
    char name[64];
    char version[32];
    char arch[16];
    uint32_t file_count;
    uint64_t payload_size;
    char sha256[65];
} aosin_header_t;

typedef struct {
    char path[AOSIN_MAX_ENTRY_PATH];
    uint64_t size;
} aosin_entry_t;

typedef struct {
    aosin_header_t header;
    char description[256];
    char app_entrypoint[128];
    char icon_path[128];
    char publisher[64];
    bool is_installed;
} aosin_pkg_info_t;

/* Create a v2 package from a real payload directory. payload_dir is
 * required; regular files only, with hard bounds on count and size.
 * Signatures are a separate pending module: verify checks integrity, not
 * publisher trust. */
int aosin_pkg_create(const char *output_file, aosin_pkg_type_t type, const char *name,
                     const char *version, const char *payload_dir);
int aosin_pkg_inspect(const char *pkg_file, aosin_pkg_info_t *info);
int aosin_pkg_install(const char *pkg_file, const char *install_root);
int aosin_pkg_remove(const char *pkg_name, const char *install_root);

/* Full integrity check: header, entry table, file sizes, payload SHA-256. */
int aosin_pkg_verify(const char *pkg_file);

#endif /* AOSIN_SPEC_H */
