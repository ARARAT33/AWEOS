#define _GNU_SOURCE
#include "archive.h"
#include "logging.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define ARCHIVE_BUFFER_SIZE 65536U

static int add_u64(uint64_t *value, uint64_t amount) {
    if (UINT64_MAX - *value < amount) { errno = EOVERFLOW; return -1; }
    *value += amount;
    return 0;
}

static int is_same_or_child(const char *path, const char *root) {
    size_t n = strlen(root);
    return strncmp(path, root, n) == 0 &&
           (path[n] == '\0' || root[n - 1] == '/' || path[n] == '/');
}

static int validate_absolute_path(const char *path) {
    if (!path || path[0] != '/' || path[1] == '/') { errno = EINVAL; return -1; }
    const char *p = path;
    while (*p) {
        while (*p == '/') p++;
        if (!*p) break;
        const char *start = p;
        while (*p && *p != '/') p++;
        size_t n = (size_t)(p - start);
        if (*p == '/' && p[1] == '/') { errno = EINVAL; return -1; }
        if ((n == 1 && start[0] == '.') ||
            (n == 2 && start[0] == '.' && start[1] == '.')) {
            errno = EINVAL;
            return -1;
        }
    }
    return 0;
}

static int ensure_directory(const char *path) {
    if (mkdir(path, 0700) == 0) return 0;
    if (errno != EEXIST) return -1;
    struct stat st;
    if (lstat(path, &st) != 0 || !S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode)) {
        errno = ELOOP;
        return -1;
    }
    return 0;
}

static int ensure_parent_directories(const char *path) {
    char *copy = strdup(path);
    if (!copy) return -1;
    for (char *p = copy + 1; *p; ++p) {
        if (*p != '/') continue;
        *p = '\0';
        if (ensure_directory(copy) != 0) { int saved = errno; free(copy); errno = saved; return -1; }
        *p = '/';
    }
    int result = ensure_directory(copy);
    int saved = errno;
    free(copy);
    errno = saved;
    return result;
}

static int split_destination(const char *destination, char **parent, char **leaf) {
    if (validate_absolute_path(destination) != 0) return -1;
    char *copy = strdup(destination);
    if (!copy) return -1;
    size_t n = strlen(copy);
    while (n > 1 && copy[n - 1] == '/') copy[--n] = '\0';
    char *slash = strrchr(copy, '/');
    if (!slash || slash[1] == '\0') { free(copy); errno = EINVAL; return -1; }
    *leaf = strdup(slash + 1);
    if (!*leaf) { free(copy); return -1; }
    if (slash == copy) copy[1] = '\0'; else *slash = '\0';
    *parent = copy;
    return 0;
}

static int write_all(int fd, const unsigned char *buffer, size_t size) {
    size_t done = 0;
    while (done < size) {
        ssize_t n = write(fd, buffer + done, size - done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { if (n == 0) errno = EIO; return -1; }
        done += (size_t)n;
    }
    return 0;
}

static int compare_files(int source_fd, int destination_fd, uint64_t size) {
    unsigned char a[ARCHIVE_BUFFER_SIZE], b[ARCHIVE_BUFFER_SIZE];
    uint64_t offset = 0;
    while (offset < size) {
        size_t want = (size_t)((size - offset) > sizeof(a) ? sizeof(a) : size - offset);
        ssize_t na;
        ssize_t nb;
        do { na = pread(source_fd, a, want, (off_t)offset); } while (na < 0 && errno == EINTR);
        do { nb = pread(destination_fd, b, want, (off_t)offset); } while (nb < 0 && errno == EINTR);
        if (na < 0 || nb < 0) return -1;
        if (na == 0 || na != nb || memcmp(a, b, (size_t)na) != 0) { errno = EIO; return -1; }
        offset += (uint64_t)na;
    }
    return 0;
}

static int copy_regular_file(const char *source, const char *destination,
                             const struct stat *expected, aweos_archive_stats_t *stats) {
    int in = open(source, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (in < 0) return -1;
    struct stat before;
    if (fstat(in, &before) != 0) { int e = errno; close(in); errno = e; return -1; }
    if (!S_ISREG(before.st_mode) || before.st_dev != expected->st_dev || before.st_ino != expected->st_ino) {
        close(in); errno = ESTALE; return -1;
    }
    int out = open(destination, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (out < 0) { int e = errno; close(in); errno = e; return -1; }

    unsigned char buffer[ARCHIVE_BUFFER_SIZE];
    uint64_t copied = 0;
    int result = 0;
    for (;;) {
        ssize_t n = read(in, buffer, sizeof(buffer));
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { result = -1; break; }
        if (n == 0) break;
        if (write_all(out, buffer, (size_t)n) != 0 || add_u64(&copied, (uint64_t)n) != 0) {
            result = -1; break;
        }
    }

    struct stat after;
    if (result == 0 && (fstat(in, &after) != 0 || copied != (uint64_t)before.st_size ||
        after.st_size != before.st_size || after.st_mtim.tv_sec != before.st_mtim.tv_sec ||
        after.st_mtim.tv_nsec != before.st_mtim.tv_nsec || after.st_ctim.tv_sec != before.st_ctim.tv_sec ||
        after.st_ctim.tv_nsec != before.st_ctim.tv_nsec)) { errno = ESTALE; result = -1; }
    if (result == 0 && fchown(out, before.st_uid, before.st_gid) != 0) result = -1;
    if (result == 0 && fchmod(out, before.st_mode & 0777) != 0) result = -1;
    if (result == 0) {
        struct timespec times[2] = {before.st_atim, before.st_mtim};
        if (futimens(out, times) != 0) result = -1;
    }
    if (result == 0 && fsync(out) != 0) result = -1;
    if (result == 0 && compare_files(in, out, copied) != 0) result = -1;
    if (result == 0) {
        struct stat final_source;
        if (fstat(in, &final_source) != 0 || final_source.st_size != before.st_size ||
            final_source.st_mtim.tv_sec != before.st_mtim.tv_sec ||
            final_source.st_mtim.tv_nsec != before.st_mtim.tv_nsec ||
            final_source.st_ctim.tv_sec != before.st_ctim.tv_sec ||
            final_source.st_ctim.tv_nsec != before.st_ctim.tv_nsec) {
            errno = ESTALE; result = -1;
        }
    }
    int saved = errno;
    if (close(out) != 0 && result == 0) { saved = errno; result = -1; }
    if (close(in) != 0 && result == 0) { saved = errno; result = -1; }
    if (result != 0) { errno = saved; return -1; }
    if (add_u64(&stats->total_files, 1) != 0 || add_u64(&stats->total_bytes, copied) != 0) return -1;
    return 0;
}

static int copy_symlink(int source_dir_fd, const char *name, const char *destination,
                        const struct stat *st, aweos_archive_stats_t *stats) {
    size_t cap = st->st_size > 0 ? (size_t)st->st_size + 1U : 256U;
    if (cap > 1024U * 1024U) { errno = ENAMETOOLONG; return -1; }
    char *target = NULL;
    ssize_t n;
    for (;;) {
        char *next = realloc(target, cap);
        if (!next) { free(target); return -1; }
        target = next;
        n = readlinkat(source_dir_fd, name, target, cap);
        if (n < 0) { int e = errno; free(target); errno = e; return -1; }
        if ((size_t)n < cap) break;
        if (cap >= 1024U * 1024U) { free(target); errno = ENAMETOOLONG; return -1; }
        cap *= 2U;
    }
    target[n] = '\0';

    /*
     * Read the link relative to the already-open source directory, then make
     * sure the directory entry still names the same symlink. This avoids
     * resolving a re-parented source path and rejects replacement races.
     */
    struct stat after;
    if (fstatat(source_dir_fd, name, &after, AT_SYMLINK_NOFOLLOW) != 0) {
        int e = errno;
        free(target);
        errno = e;
        return -1;
    }
    if (!S_ISLNK(after.st_mode) ||
        after.st_dev != st->st_dev || after.st_ino != st->st_ino ||
        after.st_ctim.tv_sec != st->st_ctim.tv_sec ||
        after.st_ctim.tv_nsec != st->st_ctim.tv_nsec ||
        after.st_mtim.tv_sec != st->st_mtim.tv_sec ||
        after.st_mtim.tv_nsec != st->st_mtim.tv_nsec) {
        free(target);
        errno = ESTALE;
        return -1;
    }

    int result = symlink(target, destination);
    int saved = errno;
    free(target);
    if (result != 0) { errno = saved; return -1; }
    if (lchown(destination, st->st_uid, st->st_gid) != 0) return -1;
    struct timespec times[2] = {st->st_atim, st->st_mtim};
    if (utimensat(AT_FDCWD, destination, times, AT_SYMLINK_NOFOLLOW) != 0) return -1;
    if (add_u64(&stats->total_files, 1) != 0 || add_u64(&stats->total_bytes, (uint64_t)n) != 0) return -1;
    return 0;
}

static int copy_directory(const char *source, const char *destination,
                          const struct stat *expected, aweos_archive_stats_t *stats) {
    int source_fd = open(source, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (source_fd < 0) return -1;
    struct stat before;
    if (fstat(source_fd, &before) != 0) {
        int saved = errno; close(source_fd); errno = saved; return -1;
    }
    if (before.st_dev != expected->st_dev || before.st_ino != expected->st_ino) {
        close(source_fd); errno = ESTALE; return -1;
    }
    if (mkdir(destination, 0700) != 0) {
        int saved = errno; close(source_fd); errno = saved; return -1;
    }
    int destination_fd = open(destination, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (destination_fd < 0) {
        int saved = errno; close(source_fd); errno = saved; return -1;
    }
    int duplicate_fd = dup(source_fd);
    if (duplicate_fd < 0) {
        int saved = errno; close(source_fd); close(destination_fd); errno = saved; return -1;
    }
    DIR *dir = fdopendir(duplicate_fd);
    if (!dir) {
        int saved = errno; close(duplicate_fd); close(source_fd); close(destination_fd); errno = saved; return -1;
    }

    int result = add_u64(&stats->total_directories, 1);
    int saved = result == 0 ? 0 : errno;
    while (result == 0) {
        errno = 0;
        struct dirent *entry = readdir(dir);
        if (!entry) {
            if (errno != 0) { saved = errno; result = -1; }
            break;
        }
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        char *src_child = NULL, *dst_child = NULL;
        if (asprintf(&src_child, "%s/%s", source, entry->d_name) < 0 ||
            asprintf(&dst_child, "%s/%s", destination, entry->d_name) < 0) {
            free(src_child); free(dst_child); saved = errno ? errno : ENOMEM; result = -1; break;
        }
        struct stat st;
        if (fstatat(source_fd, entry->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) {
            saved = errno; result = -1;
        } else if (S_ISDIR(st.st_mode)) {
            if (copy_directory(src_child, dst_child, &st, stats) != 0) { saved = errno; result = -1; }
        } else if (S_ISREG(st.st_mode)) {
            if (copy_regular_file(src_child, dst_child, &st, stats) != 0) { saved = errno; result = -1; }
        } else if (S_ISLNK(st.st_mode)) {
            if (copy_symlink(source_fd, entry->d_name, dst_child, &st, stats) != 0) { saved = errno; result = -1; }
        } else {
            LOGE("Refusing unsupported special file '%s' (mode=%o)", entry->d_name, (unsigned)st.st_mode);
            saved = ENOTSUP; result = -1;
        }
        free(src_child); free(dst_child);
    }

    if (closedir(dir) != 0 && result == 0) { saved = errno; result = -1; }
    struct stat after;
    if (result == 0 && fstat(source_fd, &after) != 0) { saved = errno; result = -1; }
    if (result == 0 && (after.st_mtim.tv_sec != before.st_mtim.tv_sec ||
        after.st_mtim.tv_nsec != before.st_mtim.tv_nsec ||
        after.st_ctim.tv_sec != before.st_ctim.tv_sec ||
        after.st_ctim.tv_nsec != before.st_ctim.tv_nsec)) { saved = ESTALE; result = -1; }
    if (result == 0 && fchown(destination_fd, before.st_uid, before.st_gid) != 0) { saved = errno; result = -1; }
    if (result == 0 && fchmod(destination_fd, before.st_mode & 0777) != 0) { saved = errno; result = -1; }
    if (result == 0) {
        struct timespec times[2] = {before.st_atim, before.st_mtim};
        if (futimens(destination_fd, times) != 0) { saved = errno; result = -1; }
    }
    if (result == 0 && fsync(destination_fd) != 0) { saved = errno; result = -1; }
    if (close(destination_fd) != 0 && result == 0) { saved = errno; result = -1; }
    if (close(source_fd) != 0 && result == 0) { saved = errno; result = -1; }
    if (result != 0) errno = saved ? saved : EIO;
    return result;
}

static int remove_archive_entry(const char *path, const struct stat *st, int type, struct FTW *ftw) {
    (void)st; (void)ftw;
    if (type == FTW_DP || type == FTW_D) (void)chmod(path, 0700);
    return remove(path);
}

int aweos_archive_directory(const char *src_dir, const char *dest_dir, aweos_archive_stats_t *stats) {
    if (!src_dir || !dest_dir || !stats || !*src_dir || !*dest_dir) return AWEOS_ERR_INVALID_PARAM;
    memset(stats, 0, sizeof(*stats));
    char *source_real = realpath(src_dir, NULL);
    if (!source_real) { LOGE("Cannot resolve archive source '%s': %s", src_dir, strerror(errno)); return AWEOS_ERR_IO; }
    char *parent = NULL, *leaf = NULL;
    if (split_destination(dest_dir, &parent, &leaf) != 0) { free(source_real); return AWEOS_ERR_INVALID_PARAM; }
    if (is_same_or_child(parent, source_real)) {
        LOGE("Refusing recursive archive destination '%s' inside '%s'", dest_dir, source_real);
        free(source_real); free(parent); free(leaf); return AWEOS_ERR_INVALID_PARAM;
    }
    if (ensure_parent_directories(parent) != 0) {
        LOGE("Cannot create/open archive parent '%s': %s", parent, strerror(errno));
        free(source_real); free(parent); free(leaf); return AWEOS_ERR_IO;
    }
    char *parent_real = realpath(parent, NULL);
    if (!parent_real || is_same_or_child(parent_real, source_real)) {
        LOGE("Refusing unsafe archive parent '%s'", parent);
        free(parent_real); free(source_real); free(parent); free(leaf); return AWEOS_ERR_INVALID_PARAM;
    }
    struct stat existing;
    if (lstat(dest_dir, &existing) == 0 || errno != ENOENT) {
        LOGE("Archive destination '%s' already exists or cannot be checked; refusing to overwrite", dest_dir);
        free(parent_real); free(source_real); free(parent); free(leaf); return AWEOS_ERR_IO;
    }
    struct stat source_stat;
    if (lstat(source_real, &source_stat) != 0 || !S_ISDIR(source_stat.st_mode)) {
        free(parent_real); free(source_real); free(parent); free(leaf); return AWEOS_ERR_IO;
    }
    LOGI("Archiving user data '%s' -> '%s'", source_real, dest_dir);
    int result = copy_directory(source_real, dest_dir, &source_stat, stats);
    if (result == 0 && chmod(dest_dir, 0700) != 0) result = -1;
    if (result != 0) {
        int saved = errno;
        LOGE("Data preservation failed for '%s': %s", dest_dir, strerror(saved));
        (void)nftw(dest_dir, remove_archive_entry, 32, FTW_DEPTH | FTW_PHYS);
        stats->verified = false;
        free(parent_real); free(source_real); free(parent); free(leaf);
        errno = saved;
        return AWEOS_ERR_IO;
    }
    stats->verified = true;
    LOGI("Data preservation verified: %llu file(s), %llu dir(s), %llu byte(s)",
         (unsigned long long)stats->total_files,
         (unsigned long long)stats->total_directories,
         (unsigned long long)stats->total_bytes);
    free(parent_real); free(source_real); free(parent); free(leaf);
    return AWEOS_OK;
}
