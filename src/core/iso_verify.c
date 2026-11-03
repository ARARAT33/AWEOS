#define _GNU_SOURCE
#include "iso_verify.h"
#include "logging.h"
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define AWEOS_MIN_ISO_SIZE (1024U * 1024U)

int aweos_iso_validate(const char *iso_path, aweos_iso_manifest_t *manifest) {
    if (!iso_path || !*iso_path || !manifest) return AWEOS_ERR_INVALID_PARAM;
    memset(manifest, 0, sizeof(*manifest));

    /*
     * A file-size check is not an integrity check. The previous implementation
     * marked every file larger than 1 MiB as valid and filled in a hard-coded
     * SHA-256 of the empty string. Until the caller can provide a trusted
     * expected digest (for example from signed release metadata), fail closed.
     *
     * O_NOFOLLOW prevents an updater from validating a symlink in place of the
     * selected ISO. O_NONBLOCK ensures a FIFO cannot hang the updater before
     * fstat rejects non-regular files.
     */
    int fd = open(iso_path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        LOGE("Failed to open ISO candidate without following symlinks '%s': %s",
             iso_path, strerror(errno));
        return AWEOS_ERR_IO;
    }

    struct stat st;
    if (fstat(fd, &st) != 0) {
        int saved_errno = errno;
        (void)close(fd);
        errno = saved_errno;
        LOGE("Failed to inspect ISO candidate '%s': %s", iso_path, strerror(errno));
        return AWEOS_ERR_IO;
    }

    if (!S_ISREG(st.st_mode) || st.st_size < 0) {
        (void)close(fd);
        LOGE("ISO candidate is not a regular file; refusing to validate '%s'", iso_path);
        return AWEOS_ERR_VERIFY;
    }

    manifest->size_bytes = (uint64_t)st.st_size;
    if (close(fd) != 0) {
        LOGE("Failed to close ISO candidate '%s': %s", iso_path, strerror(errno));
        memset(manifest, 0, sizeof(*manifest));
        return AWEOS_ERR_IO;
    }

    if (manifest->size_bytes < AWEOS_MIN_ISO_SIZE) {
        LOGE("ISO candidate '%s' is too small (%llu bytes)",
             iso_path, (unsigned long long)manifest->size_bytes);
        return AWEOS_ERR_VERIFY;
    }

    LOGE("Refusing to mark ISO candidate '%s' valid: no trusted expected SHA-256 was supplied; file size alone does not establish integrity",
         iso_path);
    return AWEOS_ERR_VERIFY;
}
