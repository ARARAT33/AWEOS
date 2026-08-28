#ifndef AWEOS_ARCHIVE_H
#define AWEOS_ARCHIVE_H

#include "types.h"

typedef struct {
    uint64_t total_files;
    uint64_t total_directories;
    uint64_t total_bytes;
    bool verified;
} aweos_archive_stats_t;

int aweos_archive_directory(const char *src_dir, const char *dest_dir, aweos_archive_stats_t *stats);

#endif /* AWEOS_ARCHIVE_H */
