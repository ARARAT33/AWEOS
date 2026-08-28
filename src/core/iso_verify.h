#ifndef AWEOS_ISO_VERIFY_H
#define AWEOS_ISO_VERIFY_H

#include "types.h"

typedef struct {
    char version[32];
    char arch[32];
    char build_id[64];
    uint64_t size_bytes;
    bool is_valid;
    char checksum_sha256[65];
} aweos_iso_manifest_t;

int aweos_iso_validate(const char *iso_path, aweos_iso_manifest_t *manifest);

#endif /* AWEOS_ISO_VERIFY_H */
