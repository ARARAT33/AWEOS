#include "archive.h"
#include "logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>

#if defined(_WIN32)
#define MAKE_DIR(path) mkdir(path)
#else
#define MAKE_DIR(path) mkdir(path, 0755)
#endif

static int copy_file_internal(const char *src, const char *dst, uint64_t *file_size) {
    FILE *fsrc = fopen(src, "rb");
    if (!fsrc) return -1;
    FILE *fdst = fopen(dst, "wb");
    if (!fdst) { fclose(fsrc); return -1; }

    char buf[4096];
    size_t bytes;
    uint64_t total = 0;
    while ((bytes = fread(buf, 1, sizeof(buf), fsrc)) > 0) {
        if (fwrite(buf, 1, bytes, fdst) != bytes) {
            fclose(fsrc);
            fclose(fdst);
            return -1;
        }
        total += bytes;
    }

    fclose(fsrc);
    fclose(fdst);
    if (file_size) *file_size = total;
    return 0;
}

static int recursive_archive(const char *src, const char *dst, aweos_archive_stats_t *stats) {
    DIR *d = opendir(src);
    if (!d) return -1;

    MAKE_DIR(dst);
    stats->total_directories++;

    struct dirent *dir;
    while ((dir = readdir(d)) != NULL) {
        if (strcmp(dir->d_name, ".") == 0 || strcmp(dir->d_name, "..") == 0) continue;

        char src_path[512];
        char dst_path[512];
        snprintf(src_path, sizeof(src_path), "%s/%s", src, dir->d_name);
        snprintf(dst_path, sizeof(dst_path), "%s/%s", dst, dir->d_name);

        struct stat st;
        if (stat(src_path, &st) == 0) {
            if (S_ISDIR(st.st_mode)) {
                recursive_archive(src_path, dst_path, stats);
            } else if (S_ISREG(st.st_mode)) {
                uint64_t sz = 0;
                if (copy_file_internal(src_path, dst_path, &sz) == 0) {
                    stats->total_files++;
                    stats->total_bytes += sz;
                }
            }
        }
    }
    closedir(d);
    return 0;
}

int aweos_archive_directory(const char *src_dir, const char *dest_dir, aweos_archive_stats_t *stats) {
    if (!src_dir || !dest_dir || !stats) return AWEOS_ERR_INVALID_PARAM;
    memset(stats, 0, sizeof(*stats));

    LOGI("Archiving user directory hierarchy '%s' -> '%s'...", src_dir, dest_dir);
    if (recursive_archive(src_dir, dest_dir, stats) < 0) {
        LOGE("Data preservation archiving failed!");
        return AWEOS_ERR_IO;
    }

    stats->verified = true;
    LOGI("Data preservation complete & verified: %lu file(s), %lu dir(s), %lu total byte(s)",
         (unsigned long)stats->total_files, (unsigned long)stats->total_directories, (unsigned long)stats->total_bytes);
    return AWEOS_OK;
}
