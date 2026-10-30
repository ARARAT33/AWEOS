#ifndef AWEOS_ARCHIVE_H
#define AWEOS_ARCHIVE_H

#include "types.h"

typedef struct {
    uint64_t total_files;       /* Regular files plus preserved symbolic links. */
    uint64_t total_directories;
    uint64_t total_bytes;       /* File contents plus symbolic-link target bytes. */
    bool verified;
} aweos_archive_stats_t;

/*
 * Copy a directory tree into a new, absolute destination directory.
 *
 * Safety contract:
 * - The destination must not already exist; existing backups are never overwritten.
 * - Destination parents are checked without following symlinks; missing parents are
 *   created with mode 0700. Dot/dot-dot and recursive destinations are rejected.
 * - Regular file bytes are copied and read back for byte-for-byte verification.
 *   Ownership, rwx permissions, and atime/mtime are preserved where permitted.
 * - Symbolic links are copied as links; their targets are never followed.
 * - FIFOs, sockets, and device nodes are rejected. On failure, only the newly-created
 *   incomplete destination tree is removed.
 * - POSIX ACLs, extended attributes, and hard-link relationships are not preserved yet.
 */
int aweos_archive_directory(const char *src_dir, const char *dest_dir, aweos_archive_stats_t *stats);

#endif /* AWEOS_ARCHIVE_H */
