#define _GNU_SOURCE
#include "../archive.h"
#include "../transaction.h"
#include <assert.h>
#include <errno.h>
#include <ftw.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int remove_cb(const char *path, const struct stat *st, int type, struct FTW *ftw) {
    (void)st; (void)type; (void)ftw; return remove(path);
}
static void cleanup(const char *path) { (void)nftw(path, remove_cb, 32, FTW_DEPTH | FTW_PHYS); }
static char *join(const char *a, const char *b) { char *p = NULL; assert(asprintf(&p, "%s/%s", a, b) >= 0); return p; }
static void write_bytes(const char *path, const void *data, size_t length) {
    FILE *f = fopen(path, "wb"); assert(f); assert(fwrite(data, 1, length, f) == length); assert(fclose(f) == 0);
}
static void write_file(const char *path, const char *data) { write_bytes(path, data, strlen(data)); }
static unsigned char *read_bytes(const char *path, size_t *length) {
    FILE *f = fopen(path, "rb"); assert(f); assert(fseek(f, 0, SEEK_END) == 0); long n = ftell(f); assert(n >= 0); rewind(f);
    unsigned char *data = calloc((size_t)n + 1, 1); assert(data); assert(fread(data, 1, (size_t)n, f) == (size_t)n); assert(fclose(f) == 0); *length = (size_t)n; return data;
}
static char *read_file(const char *path) {
    size_t length = 0; unsigned char *data = read_bytes(path, &length); (void)length; return (char *)data;
}

/* Keep this test focused on the preservation gate; unrelated stages are stubbed. */
int aweos_iso_validate(const char *iso_path, aweos_iso_manifest_t *manifest) {
    (void)iso_path; (void)manifest; return AWEOS_ERR_GENERIC;
}
int aweos_boot_configure_limine(const char *target_dir, aweos_boot_mode_t boot_mode) {
    (void)target_dir; (void)boot_mode; return AWEOS_OK;
}

int main(void) {
    char root[] = "/tmp/aweos-archive-test.XXXXXX";
    assert(mkdtemp(root));
    char *src = join(root, "home"); assert(mkdir(src, 0700) == 0);
    char *nested = join(src, "docs"); assert(mkdir(nested, 0750) == 0);
    char *empty = join(src, "empty"); assert(mkdir(empty, 0700) == 0);
    char *file1 = join(src, "profile.txt"); write_file(file1, "AWEOS user profile\n");
    char *file2 = join(nested, "data.bin");
    const unsigned char binary_payload[] = {0x00, 0x41, 0x57, 0x45, 0x00, 0xff, 0x10, 0x7f};
    write_bytes(file2, binary_payload, sizeof(binary_payload));
    char *outside = join(root, "outside-secret"); write_file(outside, "must not be followed\n");
    char *linkpath = join(src, "outside-link"); assert(symlink(outside, linkpath) == 0);
    char *archive_parent = join(root, "archive");
    char *dest = join(archive_parent, "home");

    aweos_archive_stats_t stats;
    assert(aweos_archive_directory(src, dest, &stats) == AWEOS_OK);
    assert(stats.verified);
    assert(stats.total_files == 3);
    assert(stats.total_directories == 3);
    char *copy1 = join(dest, "profile.txt");
    char *copy_docs = join(dest, "docs");
    char *copy2 = join(copy_docs, "data.bin");
    char *copylink = join(dest, "outside-link");
    char *a = read_file(file1), *b = read_file(copy1); assert(strcmp(a,b)==0); free(a); free(b);
    size_t source_length = 0, copied_length = 0;
    unsigned char *source_bytes = read_bytes(file2, &source_length);
    unsigned char *copied_bytes = read_bytes(copy2, &copied_length);
    assert(source_length == sizeof(binary_payload) && copied_length == source_length);
    assert(memcmp(source_bytes, copied_bytes, source_length) == 0);
    free(source_bytes); free(copied_bytes);
    struct stat source_mode, copied_mode, root_mode;
    assert(stat(file1, &source_mode) == 0 && stat(copy1, &copied_mode) == 0);
    assert((source_mode.st_mode & 0777) == (copied_mode.st_mode & 0777));
    assert(stat(dest, &root_mode) == 0 && (root_mode.st_mode & 0777) == 0700);
    char target[PATH_MAX]; ssize_t n = readlink(copylink, target, sizeof(target)-1); assert(n > 0); target[n] = 0; assert(strcmp(target, outside)==0);

    char *collision = join(root, "collision"); assert(mkdir(collision, 0700) == 0);
    char *sentinel = join(collision, "keep.txt"); write_file(sentinel, "do not overwrite");
    assert(aweos_archive_directory(src, collision, &stats) == AWEOS_ERR_IO);
    a = read_file(sentinel); assert(strcmp(a, "do not overwrite")==0); free(a);

    char *inside = join(src, "backup");
    assert(aweos_archive_directory(src, inside, &stats) == AWEOS_ERR_INVALID_PARAM);
    assert(access(inside, F_OK) != 0);
    char *inside_parent = join(src, "new-parent");
    char *inside_deep = join(inside_parent, "backup");
    assert(aweos_archive_directory(src, inside_deep, &stats) == AWEOS_ERR_INVALID_PARAM);
    assert(access(inside_parent, F_OK) != 0);
    char *linked_parent = join(root, "linked-parent");
    assert(symlink(archive_parent, linked_parent) == 0);
    char *linked_dest = join(linked_parent, "should-not-exist");
    assert(aweos_archive_directory(src, linked_dest, &stats) == AWEOS_ERR_IO);
    char *linked_target = join(archive_parent, "should-not-exist");
    assert(access(linked_target, F_OK) != 0);

    char *traversal_parent = join(root, "must-not-be-created");
    char *traversal_path = NULL;
    assert(asprintf(&traversal_path, "%s/../archive/escape", traversal_parent) >= 0);
    assert(aweos_archive_directory(src, traversal_path, &stats) == AWEOS_ERR_INVALID_PARAM);
    assert(access(traversal_parent, F_OK) != 0);

    char *badsrc = join(root, "badsrc"); assert(mkdir(badsrc, 0700)==0);
    char *badfile = join(badsrc, "partial.txt"); write_file(badfile, "partial archive must be removed");
    char *fifo = join(badsrc, "pipe"); assert(mkfifo(fifo, 0600)==0);
    char *baddest = join(root, "bad-archive");
    assert(aweos_archive_directory(badsrc, baddest, &stats) == AWEOS_ERR_IO);
    assert(errno == ENOTSUP);
    assert(!stats.verified);
    assert(access(baddest, F_OK) != 0);

    aweos_tx_config_t tx_config = {0};
    snprintf(tx_config.preserve_src, sizeof(tx_config.preserve_src), "%s", badsrc);
    snprintf(tx_config.preserve_dst, sizeof(tx_config.preserve_dst), "%s", baddest);
    aweos_transaction_t tx;
    assert(aweos_tx_init(&tx, &tx_config) == AWEOS_OK);
    assert(aweos_tx_preserve(&tx) == AWEOS_ERR_IO);
    assert(tx.state == TX_STATE_FAILED);
    assert(strstr(tx.error_msg, "Operation not supported") != NULL);
    assert(errno == ENOTSUP);

    memset(&tx_config, 0, sizeof(tx_config));
    snprintf(tx_config.preserve_src, sizeof(tx_config.preserve_src), "%s", src);
    assert(aweos_tx_init(&tx, &tx_config) == AWEOS_OK);
    assert(aweos_tx_preserve(&tx) == AWEOS_ERR_INVALID_PARAM);
    assert(tx.state == TX_STATE_FAILED);
    assert(strstr(tx.error_msg, "Both preservation source and destination") != NULL);
    assert(errno == EINVAL);

    /* Deep paths exceed the old fixed 512-byte buffers. */
    char *longsrc = join(root, "long-home"); assert(mkdir(longsrc, 0700) == 0);
    char *long_source_path = strdup(longsrc); assert(long_source_path);
    char component[81]; memset(component, 'd', 80); component[80] = '\0';
    for (int i = 0; i < 9; ++i) {
        char *next = join(long_source_path, component);
        assert(mkdir(next, 0700) == 0);
        free(long_source_path); long_source_path = next;
    }
    char *long_file = join(long_source_path, "deep.txt"); write_file(long_file, "deep path survives");
    char *longdest = join(root, "long-archive");
    assert(aweos_archive_directory(longsrc, longdest, &stats) == AWEOS_OK && stats.verified);
    char *long_copy_dir = strdup(longdest); assert(long_copy_dir);
    for (int i = 0; i < 9; ++i) {
        char *next = join(long_copy_dir, component);
        free(long_copy_dir); long_copy_dir = next;
    }
    char *long_copy = join(long_copy_dir, "deep.txt");
    a = read_file(long_copy); assert(strcmp(a, "deep path survives") == 0); free(a);

    cleanup(root);
    free(src); free(nested); free(empty); free(file1); free(file2); free(outside); free(linkpath);
    free(archive_parent); free(dest); free(copy1); free(copy_docs); free(copy2); free(copylink);
    free(collision); free(sentinel); free(inside); free(inside_parent); free(inside_deep);
    free(linked_parent); free(linked_dest); free(linked_target);
    free(traversal_parent); free(traversal_path);
    free(badsrc); free(badfile); free(fifo); free(baddest);
    free(longsrc); free(long_source_path); free(long_file); free(longdest); free(long_copy_dir); free(long_copy);
    puts("PASS: archive copies and verifies regular files, preserves symlink objects, refuses collisions/recursion/special files, and removes partial output.");
    return 0;
}
