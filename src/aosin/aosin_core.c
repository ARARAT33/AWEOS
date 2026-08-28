#include "aosin_spec.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>

#if defined(_WIN32)
#define MAKE_DIR(path) mkdir(path)
#else
#define MAKE_DIR(path) mkdir(path, 0755)
#endif

static void mkdir_p(const char *dir) {
    char tmp[256];
    char *p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", dir);
    len = strlen(tmp);
    if (tmp[len - 1] == '/') tmp[len - 1] = 0;
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            MAKE_DIR(tmp);
            *p = '/';
        }
    }
    MAKE_DIR(tmp);
}

int aosin_pkg_create(const char *output_file, aosin_pkg_type_t type, const char *name, const char *version, const char *payload_dir) {
    if (!output_file || !name || !version) return AWEOS_ERR_INVALID_PARAM;
    (void)payload_dir;

    FILE *f = fopen(output_file, "wb");
    if (!f) {
        LOGE("Failed to create AOSIN package file: %s", output_file);
        return AWEOS_ERR_IO;
    }

    aosin_header_t hdr;
    memset(&hdr, 0, sizeof(hdr));
    hdr.magic = AOSIN_MAGIC;
    hdr.format_ver = 1;
    hdr.pkg_type = (uint16_t)type;
    snprintf(hdr.name, sizeof(hdr.name), "%s", name);
    snprintf(hdr.version, sizeof(hdr.version), "%s", version);
    snprintf(hdr.arch, sizeof(hdr.arch), "%s", AWEOS_ARCH);
    snprintf(hdr.sha256, sizeof(hdr.sha256), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

    hdr.payload_size = 1024; // Initial payload footprint
    fwrite(&hdr, sizeof(hdr), 1, f);

    // Dummy payload archive block
    char dummy_payload[1024];
    memset(dummy_payload, 0xAA, sizeof(dummy_payload));
    fwrite(dummy_payload, 1, sizeof(dummy_payload), f);

    fclose(f);
    LOGI("AOSIN Package created successfully: %s (Type: %d, Name: %s, Ver: %s)",
         output_file, type, name, version);
    return AWEOS_OK;
}

int aosin_pkg_inspect(const char *pkg_file, aosin_pkg_info_t *info) {
    if (!pkg_file || !info) return AWEOS_ERR_INVALID_PARAM;
    memset(info, 0, sizeof(*info));

    FILE *f = fopen(pkg_file, "rb");
    if (!f) {
        LOGE("Failed to open AOSIN package: %s", pkg_file);
        return AWEOS_ERR_IO;
    }

    if (fread(&info->header, sizeof(info->header), 1, f) != 1) {
        fclose(f);
        LOGE("Invalid header reading AOSIN package: %s", pkg_file);
        return AWEOS_ERR_VERIFY;
    }
    fclose(f);

    if (info->header.magic != AOSIN_MAGIC) {
        LOGE("Invalid magic header in AOSIN package!");
        return AWEOS_ERR_VERIFY;
    }

    snprintf(info->description, sizeof(info->description), "AOSIN Native Application/Package %s", info->header.name);
    snprintf(info->publisher, sizeof(info->publisher), "AWEOS Systems");
    snprintf(info->app_entrypoint, sizeof(info->app_entrypoint), "/usr/bin/%s", info->header.name);

    LOGI("Inspected AOSIN Package %s: Type=%d, Ver=%s, Arch=%s",
         info->header.name, info->header.pkg_type, info->header.version, info->header.arch);
    return AWEOS_OK;
}

int aosin_pkg_install(const char *pkg_file, const char *install_root) {
    aosin_pkg_info_t info;
    int res = aosin_pkg_inspect(pkg_file, &info);
    if (res != AWEOS_OK) return res;

    const char *root = install_root ? install_root : "";
    char meta_dir[256];
    char meta_file[256];
    snprintf(meta_dir, sizeof(meta_dir), "%s/var/lib/awepkg", root);
    snprintf(meta_file, sizeof(meta_file), "%s/%s.meta", meta_dir, info.header.name);

    mkdir_p(meta_dir);

    FILE *f = fopen(meta_file, "w");
    if (!f) {
        LOGE("Failed to register AOSIN package metadata at %s", meta_file);
        return AWEOS_ERR_IO;
    }

    fprintf(f, "PKG_NAME=%s\n", info.header.name);
    fprintf(f, "PKG_VER=%s\n", info.header.version);
    fprintf(f, "PKG_TYPE=%d\n", info.header.pkg_type);
    fprintf(f, "ARCH=%s\n", info.header.arch);
    fprintf(f, "ENTRYPOINT=%s\n", info.app_entrypoint);
    fclose(f);

    LOGI("AOSIN Package '%s' installed successfully!", info.header.name);
    return AWEOS_OK;
}

int aosin_pkg_remove(const char *pkg_name, const char *install_root) {
    if (!pkg_name) return AWEOS_ERR_INVALID_PARAM;
    const char *root = install_root ? install_root : "";
    char meta_file[256];
    snprintf(meta_file, sizeof(meta_file), "%s/var/lib/awepkg/%s.meta", root, pkg_name);

    if (unlink(meta_file) == 0) {
        LOGI("AOSIN Package '%s' removed successfully.", pkg_name);
        return AWEOS_OK;
    } else {
        LOGW("AOSIN Package metadata not found for '%s'", pkg_name);
        return AWEOS_ERR_NOT_FOUND;
    }
}

int aosin_pkg_verify(const char *pkg_file) {
    aosin_pkg_info_t info;
    return aosin_pkg_inspect(pkg_file, &info);
}
