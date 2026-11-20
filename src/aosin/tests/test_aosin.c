#define _POSIX_C_SOURCE 200809L

#include "aosin_spec.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void make_payload(const char *dir, const char *content, size_t len, int with_symlink) {
    char sub[512];
    snprintf(sub, sizeof(sub), "%s/sub", dir);
    mkdir(dir, 0755);
    mkdir(sub, 0755);
    char f1[1024];
    snprintf(f1, sizeof(f1), "%s/readme.txt", dir);
    FILE *a = fopen(f1, "wb");
    assert(a);
    fwrite(content, 1, len, a);
    fclose(a);
    char f2[1024];
    snprintf(f2, sizeof(f2), "%s/sub/data.bin", dir);
    FILE *b = fopen(f2, "wb");
    assert(b);
    fwrite(content, 1, len * 2, b);
    fclose(b);
    if (with_symlink) {
        char lnk[1024];
        snprintf(lnk, sizeof(lnk), "%s/danger.lnk", dir);
        symlink("/etc", lnk);   /* must be skipped by packaging */
    }
}

static void expect_not(const char *what, int rc, int code) {
    if (rc != code) {
        fprintf(stderr, "FAIL: %s got rc=%d want %d\n", what, rc, code);
        exit(1);
    }
}

int main(void) {
    /* 1. create a real payload package and verify it */
    mkdir("build", 0755);
    make_payload("build/app", "AWEOS real payload content", 24, 0);
    expect_not("create app1", aosin_pkg_create("build/app1.asp", PKG_TYPE_ASP, "app1", "1.0", "build/app"), AWEOS_OK);
    expect_not("verify app1", aosin_pkg_verify("build/app1.asp"), AWEOS_OK);

    aosin_pkg_info_t info;
    expect_not("inspect app1", aosin_pkg_inspect("build/app1.asp", &info), AWEOS_OK);
    if (strcmp(info.header.name, "app1") != 0 || info.header.file_count != 2) {
        fprintf(stderr, "FAIL: inspect fields\n");
        return 1;
    }
    if (info.header.payload_size != 24 + 48 || strlen(info.header.sha256) != 64) {
        fprintf(stderr, "FAIL: payload/hash size\n");
        return 1;
    }

    /* 2. tamper one payload byte: verify must fail */
    {
        FILE *f = fopen("build/app1.asp", "r+b");
        assert(f);
        if (fseek(f, -1, SEEK_END) != 0) {
            fclose(f);
            fprintf(stderr, "FAIL: seek to tamper byte\\n");
            return 1;
        }
        int original = fgetc(f);
        if (original == EOF || fseek(f, -1, SEEK_END) != 0 ||
            fputc(original ^ 0x01, f) == EOF) {
            fclose(f);
            fprintf(stderr, "FAIL: mutate package byte\\n");
            return 1;
        }
        fclose(f);
        expect_not("tampered verify", aosin_pkg_verify("build/app1.asp"), AWEOS_ERR_VERIFY);
        /* rebuild for later tests */
        expect_not("recreate app1", aosin_pkg_create("build/app1.asp", PKG_TYPE_ASP, "app1", "1.0", "build/app"), AWEOS_OK);
    }

    /* 3. symlink payload entries are skipped, never packaged or followed */
    make_payload("build/app2", "payload with symlink", 19, 1);
    expect_not("create app2", aosin_pkg_create("build/app2.asp", PKG_TYPE_ASA, "app2", "2.0", "build/app2"), AWEOS_OK);
    expect_not("inspect app2", aosin_pkg_inspect("build/app2.asp", &info), AWEOS_OK);
    if (info.header.file_count != 2) {
        fprintf(stderr, "FAIL: symlink was packaged\n");
        return 1;
    }

    /* 4. install to an isolated root, files land in the right place */
    mkdir("rootfs_test", 0755);
    expect_not("install app2", aosin_pkg_install("build/app2.asp", "rootfs_test"), AWEOS_OK);
    struct stat st;
    if (stat("rootfs_test/opt/aweos-pkg/app2/readme.txt", &st) != 0 ||
        stat("rootfs_test/opt/aweos-pkg/app2/sub/data.bin", &st) != 0) {
        fprintf(stderr, "FAIL: installed layout\n");
        return 1;
    }
    if (stat("rootfs_test/var/lib/awepkg/app2.meta", &st) != 0) {
        fprintf(stderr, "FAIL: meta file\n");
        return 1;
    }

    /* 5. reinstall of the same package fails instead of silently clobbering */
    expect_not("reinstall app2", aosin_pkg_install("build/app2.asp", "rootfs_test"), AWEOS_ERR_VERIFY);

    /* 6. remove deletes the app dir and meta; second remove is NOT_FOUND */
    expect_not("remove app2", aosin_pkg_remove("app2", "rootfs_test"), AWEOS_OK);
    expect_not("re-remove app2", aosin_pkg_remove("app2", "rootfs_test"), AWEOS_ERR_NOT_FOUND);

    /* 7. path traversal entries are rejected fail-closed */
    expect_not("traversal create", aosin_pkg_create("build/evil.asp", PKG_TYPE_ASP, "../evil", "1.0", "build/app"), AWEOS_ERR_INVALID_PARAM);

    /* 8. bad names are rejected */
    expect_not("bad name", aosin_pkg_create("build/x.asp", PKG_TYPE_ASP, "bad/name", "1.0", "build/app"), AWEOS_ERR_INVALID_PARAM);
    expect_not("bad version", aosin_pkg_create("build/x.asp", PKG_TYPE_ASP, "x", "1 0", "build/app"), AWEOS_ERR_INVALID_PARAM);

    /* 9. legacy v1 package is rejected fail-closed */
    {
        FILE *f = fopen("build/legacy.asp", "wb");
        assert(f);
        unsigned char v1[128];
        memset(v1, 0, sizeof(v1));
        v1[0] = 0x4F; v1[1] = 0x53; v1[2] = 0x49; v1[3] = 0x4E;   /* legacy magic */
        fwrite(v1, 1, sizeof(v1), f);
        fclose(f);
        expect_not("legacy v1", aosin_pkg_verify("build/legacy.asp"), AWEOS_ERR_VERIFY);
        expect_not("legacy v1 install", aosin_pkg_install("build/legacy.asp", "rootfs_test"), AWEOS_ERR_VERIFY);
    }

    /* 10. empty payload dir is rejected */
    mkdir("empty_dir", 0755);
    expect_not("empty create", aosin_pkg_create("build/empty.asp", PKG_TYPE_ASP, "empty", "1.0", "empty_dir"), AWEOS_ERR_INVALID_PARAM);

    printf("aosin: all tests passed\n");
    return 0;
}
