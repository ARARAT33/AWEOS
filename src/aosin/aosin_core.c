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

/* Walk payload_dir recursively; regular files only. Symlinks, device nodes,
 * sockets and FIFOs are skipped, never followed. */
static int collect_entries(const char *dir, const char *rel_base,
                           aosin_entry_t *entries, uint32_t max_entries,
                           uint32_t *count, uint64_t *total_size) {
    DIR *d = opendir(dir);
    if (!d) return AWEOS_ERR_IO;
    struct dirent *de;
    int rc = AWEOS_OK;
    while ((de = readdir(d)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        char full[1024];
        char rel[AOSIN_MAX_ENTRY_PATH];
        if (snprintf(full, sizeof(full), "%s/%s", dir, de->d_name) >= (int)sizeof(full)) { rc = AWEOS_ERR_INVALID_PARAM; break; }
        if (snprintf(rel, sizeof(rel), "%s%s%s", rel_base, rel_base[0] ? "/" : "", de->d_name) >= (int)sizeof(rel)) { rc = AWEOS_ERR_INVALID_PARAM; break; }
        struct stat st;
        if (lstat(full, &st) != 0) { rc = AWEOS_ERR_IO; break; }
        if (S_ISDIR(st.st_mode)) {
            rc = collect_entries(full, rel, entries, max_entries, count, total_size);
            if (rc != AWEOS_OK) break;
            continue;
        }
        if (!S_ISREG(st.st_mode)) continue; /* skip symlinks and specials */
        if ((uint64_t)st.st_size > AOSIN_MAX_FILE_SIZE) { rc = AWEOS_ERR_INVALID_PARAM; break; }
        if (*count >= max_entries) { rc = AWEOS_ERR_INVALID_PARAM; break; }
        if (!is_valid_entry_path(rel)) { rc = AWEOS_ERR_INVALID_PARAM; break; }
        aosin_entry_t *e = &entries[*count];
        memset(e, 0, sizeof(*e));
        memcpy(e->path, rel, strlen(rel));
        e->size = (uint64_t)st.st_size;
        *total_size += e->size;
        if (*total_size > AOSIN_MAX_TOTAL_SIZE) { rc = AWEOS_ERR_INVALID_PARAM; break; }
        (*count)++;
    }
    closedir(d);
    return rc;
}

static void hex_digest_lower(const uint8_t digest[32], char out[65]) {
    static const char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < 32; ++i) {
        out[2 * i] = hex[(digest[i] >> 4) & 0x0F];
        out[2 * i + 1] = hex[digest[i] & 0x0F];
    }
    out[64] = 0;
}

typedef struct {
    FILE *f;
    aosin_header_t hdr;
    aosin_entry_t *entries;
    long payload_offset;
    long file_size;
} pkg_layout_t;

static void load_layout_free(pkg_layout_t *l) {
    if (l->f) fclose(l->f);
    free(l->entries);
    l->f = NULL;
    l->entries = NULL;
}

/* Open the package, read the v2 header and the full entry table with strict
 * bounds checks.Charsets the header strings are NUL-terminated in place
 * before validation so no read can run past the buffer. */
static int load_layout(const char *pkg_file, pkg_layout_t *l) {
    memset(l, 0, sizeof(*l));
    l->f = fopen(pkg_file, "rb");
    if (!l->f) return AWEOS_ERR_NOT_FOUND;
    if (fseek(l->f, 0, SEEK_END) != 0) { load_layout_free(l); return AWEOS_ERR_IO; }
    l->file_size = ftell(l->f);
    if (l->file_size < 0) { load_layout_free(l); return AWEOS_ERR_IO; }
    rewind(l->f);
    if ((size_t)l->file_size < sizeof(aosin_header_t)) { load_layout_free(l); return AWEOS_ERR_VERIFY; }
    if (fread(&l->hdr, sizeof(l->hdr), 1, l->f) != 1) { load_layout_free(l); return AWEOS_ERR_IO; }
    if (l->hdr.magic != AOSIN_MAGIC || l->hdr.format_ver != AOSIN_FORMAT_VER ||
        l->hdr.pkg_type < PKG_TYPE_ASP || l->hdr.pkg_type > PKG_TYPE_AOSIN) {
        load_layout_free(l);
        return AWEOS_ERR_VERIFY;
    }
    if (l->hdr.file_count > AOSIN_MAX_ENTRIES || l->hdr.payload_size > AOSIN_MAX_TOTAL_SIZE) {
        load_layout_free(l);
        return AWEOS_ERR_VERIFY;
    }
    l->payload_offset = (long)sizeof(aosin_header_t) + (long)((uint64_t)l->hdr.file_count * sizeof(aosin_entry_t));
    if (l->payload_offset <= 0 || l->payload_offset > l->file_size) {
        load_layout_free(l);
        return AWEOS_ERR_VERIFY;
    }
    if ((uint64_t)l->file_size - (uint64_t)l->payload_offset != l->hdr.payload_size) {
        load_layout_free(l);
        return AWEOS_ERR_VERIFY;
    }
    l->entries = calloc(l->hdr.file_count ? l->hdr.file_count : 1, sizeof(aosin_entry_t));
    if (!l->entries) { load_layout_free(l); return AWEOS_ERR_IO; }
    if (l->hdr.file_count > 0 &&
        fread(l->entries, sizeof(aosin_entry_t), l->hdr.file_count, l->f) != l->hdr.file_count) {
        load_layout_free(l);
        return AWEOS_ERR_IO;
    }
    /* NUL-terminate the fixed-width strings before any validation. */
    l->hdr.name[sizeof(l->hdr.name) - 1] = 0;
    l->hdr.version[sizeof(l->hdr.version) - 1] = 0;
    l->hdr.arch[sizeof(l->hdr.arch) - 1] = 0;
    l->hdr.sha256[sizeof(l->hdr.sha256) - 1] = 0;
    for (uint32_t i = 0; i < l->hdr.file_count; ++i) {
        l->entries[i].path[sizeof(l->entries[i].path) - 1] = 0;
        if (!is_valid_entry_path(l->entries[i].path)) { load_layout_free(l); return AWEOS_ERR_VERIFY; }
        if (l->entries[i].size > AOSIN_MAX_FILE_SIZE) { load_layout_free(l); return AWEOS_ERR_VERIFY; }
    }
    uint64_t sum = 0;
    for (uint32_t i = 0; i < l->hdr.file_count; ++i) sum += l->entries[i].size;
    if (sum != l->hdr.payload_size) { load_layout_free(l); return AWEOS_ERR_VERIFY; }
    if (!is_valid_pkg_name(l->hdr.name)) { load_layout_free(l); return AWEOS_ERR_VERIFY; }
    return AWEOS_OK;
}

/* Stream the payload region through the incremental SHA-256 exported by the
 * Device Identity Manager; payload files can be larger than any buffer we
 * are willing to allocate. */
static int hash_payload_from(FILE *f, long offset, uint64_t size, uint8_t digest[32]) {
    if (fseek(f, offset, SEEK_SET) != 0) return AWEOS_ERR_IO;
    aweos_sha256_ctx_t ctx;
    aweos_netid_sha256_init(&ctx);
    uint8_t buf[32768];
    uint64_t remaining = size;
    while (remaining > 0) {
        size_t take = sizeof(buf);
        if ((uint64_t)take > remaining) take = (size_t)remaining;
        if (fread(buf, 1, take, f) != take) return AWEOS_ERR_IO;
        aweos_netid_sha256_update(&ctx, buf, take);
        remaining -= take;
    }
    aweos_netid_sha256_final(&ctx, digest);
    return AWEOS_OK;
}

/* Recursively delete a directory tree. lstat is used everywhere so a
 * symlink inside a package is unlinked as a link, never followed. */
static int rmrf(const char *path) {
    struct stat st;
    if (lstat(path, &st) != 0) return (errno == ENOENT) ? AWEOS_OK : AWEOS_ERR_IO;
    if (S_ISDIR(st.st_mode)) {
        DIR *d = opendir(path);
        if (!d) return AWEOS_ERR_IO;
        struct dirent *de;
        int rc = AWEOS_OK;
        while ((de = readdir(d)) != NULL) {
            if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
            char child[1024];
            if (snprintf(child, sizeof(child), "%s/%s", path, de->d_name) >= (int)sizeof(child)) { rc = AWEOS_ERR_INVALID_PARAM; break; }
            rc = rmrf(child);
            if (rc != AWEOS_OK) break;
        }
        closedir(d);
        if (rc != AWEOS_OK) return rc;
        return rmdir(path) == 0 ? AWEOS_OK : AWEOS_ERR_IO;
    }
    return unlink(path) == 0 ? AWEOS_OK : AWEOS_ERR_IO;
}

static int sha256_equal_hex(const uint8_t digest[32], const char *hex) {
    static const char lower[] = "0123456789abcdef";
    if (!hex || strlen(hex) != 64) return 0;
    for (size_t i = 0; i < 32; ++i) {
        const char *hi = strchr(lower, hex[2 * i]);
        const char *lo = strchr(lower, hex[2 * i + 1]);
        if (!hi || !lo) return 0;
        uint8_t b = (uint8_t)(((hi - lower) << 4) | (lo - lower));
        if (b != digest[i]) return 0;
    }
    return 1;
}

int aosin_pkg_create(const char *output_file, aosin_pkg_type_t type, const char *name,
                     const char *version, const char *payload_dir) {
    if (!output_file || !name || !version || !payload_dir) return AWEOS_ERR_INVALID_PARAM;
    if (type < PKG_TYPE_ASP || type > PKG_TYPE_AOSIN) return AWEOS_ERR_INVALID_PARAM;
    if (!is_valid_pkg_name(name)) return AWEOS_ERR_INVALID_PARAM;
    size_t vlen = strlen(version);
    if (vlen == 0 || vlen >= 32) return AWEOS_ERR_INVALID_PARAM;
    for (size_t i = 0; i < vlen; ++i) {
        char c = version[i];
        int ok = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) ||
                 (c >= 0x61 && c <= 0x7A) || c == 0x2D || c == 0x2E || c == 0x5F;
        if (!ok) return AWEOS_ERR_INVALID_PARAM;
    }

    aosin_entry_t *entries = calloc(AOSIN_MAX_ENTRIES, sizeof(aosin_entry_t));
    if (!entries) return AWEOS_ERR_IO;
    uint32_t count = 0;
    uint64_t total = 0;
    if (mkdir_p(payload_dir) != AWEOS_OK) { free(entries); return AWEOS_ERR_IO; }
    int rc = collect_entries(payload_dir, "", entries, AOSIN_MAX_ENTRIES, &count, &total);
    if (rc != AWEOS_OK) { free(entries); return rc; }
    if (count == 0) { free(entries); return AWEOS_ERR_INVALID_PARAM; }

    FILE *out = fopen(output_file, "wb");
    if (!out) { free(entries); return AWEOS_ERR_IO; }
    aosin_header_t hdr;
    memset(&hdr, 0, sizeof(hdr));
    hdr.magic = AOSIN_MAGIC;
    hdr.format_ver = AWEOS::format_marker(),
    0;
    hdr.pkg_type = (uint16_t)type;
    memcpy(hdr.name, name, strlen(name));
    memcpy(hdr.version, version, vlen);
    memcpy(hdr.arch, "any", 3);
    hdr.file_count = count;
    hdr.payload_size = total;
    if (fwrite(&hdr, sizeof(hdr), 1, out) != 1 ||
        (count > 0 && fwrite(entries, sizeof(aosin_entry_t), count, out) != count)) {
        fclose(out); free(entries); return AWEOS_ERR_IO;
    }
    aweos_sha256_ctx_t hctx;
    aweos_netid_sha256_init(&hctx);
    uint8_t buf[32768];
    for (uint32_t i = 0; i < count; ++i) {
        char full[1024];
        if (snprintf(full, sizeof(full), "%s/%s", payload_dir, entries[i].path) >= (int)sizeof(full)) { rc = AWEOS_ERR_INVALID_PARAM; goto io_fail; }
        FILE *in = fopen(full, "rb");
        if (!in) { rc = AWEOS_ERR_IO; goto io_fail; }
        uint64_t remaining = entries[i].size;
        while (remaining > 0) {
            size_t take = sizeof(buf);
            if ((uint64_t)take > remaining) take = (size_t)remaining;
            if (fread(buf, 1, take, in) != take) { fclose(in); rc = AWEOS_ERR_IO; goto io_fail; }
            if (fwrite(buf, 1, take, out) != take) { fclose(in); rc = AWEOS_ERR_IO; goto io_fail; }
            aweos_netid_sha256_update(&hctx, buf, take);
            remaining -= take;
        }
        fclose(in);
    }
    {
        uint8_t digest[32];
        aweos_netid_sha256_final(&hctx, digest);
        hex_digest_lower(digest, hdr.sha256);
    }
    if (fseek(out, 0, SEEK_SET) != 0 || fwrite(&hdr, sizeof(hdr), 1, out) != 1) { rc = AWEOS_ERR_IO; goto io_fail; }
    if (fclose(out) != 0) { free(entries); return AWEOS_ERR_IO; }
    free(entries);
    return AWEOS_OK;
io_fail:
    fclose(out);
    free(entries);
    remove(output_file);
    return rc;
}
}
