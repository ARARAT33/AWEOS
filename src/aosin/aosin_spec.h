#ifndef AOSIN_SPEC_H
#define AOSIN_SPEC_H

#include "../core/types.h"

#define AOSIN_MAGIC 0x4E49534F /* "OSIN" in Little-Endian */

typedef enum {
    PKG_TYPE_ASP = 1,   /* AWEOS Software Package (Payload / Library / Binary) */
    PKG_TYPE_ASA = 2,   /* AWEOS Standalone Application Bundle */
    PKG_TYPE_AOSIN = 3  /* AOSIN Multi-Package Installer Bundle */
} aosin_pkg_type_t;

typedef struct __attribute__((packed)) {
    uint32_t magic;         /* AOSIN_MAGIC */
    uint16_t format_ver;    /* Format version (e.g., 1) */
    uint16_t pkg_type;      /* aosin_pkg_type_t */
    char name[64];          /* Package identifier */
    char version[32];       /* Package version */
    char arch[16];          /* Target architecture */
    uint64_t payload_size;  /* Size of file payload */
    char sha256[65];        /* Hash manifest */
} aosin_header_t;

typedef struct {
    aosin_header_t header;
    char description[256];
    char app_entrypoint[128];
    char icon_path[128];
    char publisher[64];
    bool is_installed;
} aosin_pkg_info_t;

int aosin_pkg_create(const char *output_file, aosin_pkg_type_t type, const char *name, const char *version, const char *payload_dir);
int aosin_pkg_inspect(const char *pkg_file, aosin_pkg_info_t *info);
int aosin_pkg_install(const char *pkg_file, const char *install_root);
int aosin_pkg_remove(const char *pkg_name, const char *install_root);
int aosin_pkg_verify(const char *pkg_file);

#endif /* AOSIN_SPEC_H */
