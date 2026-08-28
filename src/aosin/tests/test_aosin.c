#include "aosin_spec.h"
#include "../core/logging.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    LOGI("Running AOSIN Package System Tests...");

    const char *asp_file = "build/test_app.asp";
    const char *asa_file = "build/test_app.asa";
    const char *aosin_file = "build/test_app.aosin";

    // Test 1: Package Creation (.asp, .asa, .aosin)
    assert(aosin_pkg_create(asp_file, PKG_TYPE_ASP, "calculator", "1.0.0", NULL) == AWEOS_OK);
    assert(aosin_pkg_create(asa_file, PKG_TYPE_ASA, "text-editor", "2.1.0", NULL) == AWEOS_OK);
    assert(aosin_pkg_create(aosin_file, PKG_TYPE_AOSIN, "media-suite", "3.0.0", NULL) == AWEOS_OK);

    // Test 2: Package Inspection
    aosin_pkg_info_t info;
    assert(aosin_pkg_inspect(asp_file, &info) == AWEOS_OK);
    assert(strcmp(info.header.name, "calculator") == 0);
    assert(info.header.pkg_type == PKG_TYPE_ASP);

    // Test 3: Package Verification
    assert(aosin_pkg_verify(asa_file) == AWEOS_OK);

    // Test 4: Package Installation & Removal
    assert(aosin_pkg_install(asp_file, "build/rootfs_test") == AWEOS_OK);
    assert(aosin_pkg_remove("calculator", "build/rootfs_test") == AWEOS_OK);

    LOGI("All AOSIN Package System Tests PASSED successfully!");
    return 0;
}
