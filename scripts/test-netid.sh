#!/usr/bin/env bash
# Device Identity Manager regression: FIPS 180-4 SHA-256 vectors, RFC 4231
# HMAC-SHA256 vector, deterministic identity derivation, fingerprint format,
# challenge/response accept and fail-closed rejection paths.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-netid-test.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT
cd "$tmp_root"

cat > netid_test.c <<'C_TEST'
#include "netid.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void sha256_hex(const uint8_t *data, size_t len, char *hex) {
    static const char digits[16] = {'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'};
    uint8_t digest[32];
    assert(aweos_netid_sha256(data, len, digest) == AWEOS_OK);
    for (unsigned i = 0; i < 32; ++i) {
        hex[2 * i] = digits[(digest[i] >> 4) & 0x0F];
        hex[2 * i + 1] = digits[digest[i] & 0x0F];
    }
    hex[64] = '\0';
}

int main(void) {
    char hex[65];

    /* FIPS 180-4: SHA-256 of the empty string. */
    sha256_hex((const uint8_t *)"", 0, hex);
    assert(strcmp(hex,
        "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855") == 0);

    /* FIPS 180-4: SHA-256 of "abc". */
    sha256_hex((const uint8_t *)"abc", 3, hex);
    assert(strcmp(hex,
        "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD") == 0);

    /* FIPS 180-4: the two-block "abcdbcde ..." message. */
    const char *two_block = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    sha256_hex((const uint8_t *)two_block, 56, hex);
    assert(strcmp(hex,
        "248D6A61D20638B8E5C026930C3E6039A33CE45964FF2167F6ECEDD419DB06C1") == 0);

    /* Multi-block streaming input must be reproducible. */
    static uint8_t million[1000000];
    memset(million, 'a', sizeof(million));
    uint8_t digest_a[32], digest_b[32];
    assert(aweos_netid_sha256(million, sizeof(million), digest_a) == AWEOS_OK);
    assert(aweos_netid_sha256(million, sizeof(million), digest_b) == AWEOS_OK);
    assert(memcmp(digest_a, digest_b, 32) == 0);
    static const uint8_t million_expected[32] = {
        0xCD,0xC7,0x6E,0x5C,0x99,0x14,0xFB,0x92,0x81,0xA1,0xC7,0xE2,0x84,0xD7,0x3E,0x67,
        0xF1,0x80,0x9A,0x48,0xA4,0x97,0x20,0x0E,0x04,0x6D,0x39,0xCC,0xC7,0x11,0x2C,0xD0
    };
    assert(memcmp(digest_a, million_expected, sizeof(million_expected)) == 0);

    /* RFC 4231 Test Case 1: key of 20 0x0b bytes, data "Hi There". */
    uint8_t key[20];
    memset(key, 0x0b, sizeof(key));
    uint8_t mac[32], mac_again[32];
    assert(aweos_netid_hmac_sha256(key, sizeof(key), (const uint8_t *)"Hi There", 8, mac) == AWEOS_OK);
    static const uint8_t expected[32] = {
        0xB0,0x34,0x4C,0x61,0xD8,0xDB,0x38,0x53,0x5C,0xA8,0xAF,0xCE,0xAF,0x0B,0xF1,0x2B,
        0x88,0x1D,0xC2,0x00,0xC9,0x83,0x3D,0xA7,0x26,0xE9,0x37,0x6C,0x2E,0x32,0xCF,0xF7
    };
    assert(memcmp(mac, expected, 32) == 0);
    assert(aweos_netid_hmac_sha256(key, sizeof(key), (const uint8_t *)"Hi There", 8, mac_again) == AWEOS_OK);
    assert(memcmp(mac, mac_again, 32) == 0);

    /* Deterministic identity derivation and distinct identities. */
    uint8_t secret_a[32], secret_b[32];
    memset(secret_a, 0x11, sizeof(secret_a));
    memset(secret_b, 0x12, sizeof(secret_b));
    aweos_device_identity_t ident_a, ident_a2, ident_b;
    assert(aweos_netid_derive(secret_a, &ident_a) == AWEOS_OK);
    assert(aweos_netid_derive(secret_a, &ident_a2) == AWEOS_OK);
    assert(aweos_netid_derive(secret_b, &ident_b) == AWEOS_OK);
    assert(memcmp(ident_a.id, ident_a2.id, 32) == 0);
    assert(strcmp(ident_a.fingerprint, ident_a2.fingerprint) == 0);
    static const uint8_t expected_identity_a[32] = {
        0x84,0x20,0x6F,0xE8,0xDC,0x1E,0xE1,0x37,0xA3,0xC4,0x02,0xA7,0xBE,0xF8,0x7E,0xFA,
        0xAC,0x07,0xCF,0xD0,0x20,0x9B,0xB6,0xA8,0xFE,0x35,0x15,0x43,0xD1,0x18,0xBD,0x2D
    };
    assert(memcmp(ident_a.id, expected_identity_a, sizeof(expected_identity_a)) == 0);
    assert(strcmp(ident_a.fingerprint, "AWE-84206FE8-DC1EE137-A3C402A7") == 0);
    assert(memcmp(ident_a.id, ident_b.id, 32) != 0);
    assert(strcmp(ident_a.fingerprint, ident_b.fingerprint) != 0);

    /* Fingerprint format: AWE-XXXXXXXX-XXXXXXXX-XXXXXXXX, uppercase hex. */
    assert(strlen(ident_a.fingerprint) == 30);
    assert(strncmp(ident_a.fingerprint, "AWE-", 4) == 0);
    assert(ident_a.fingerprint[12] == '-' && ident_a.fingerprint[21] == '-');
    for (unsigned i = 0; i < 30; ++i) {
        if (i < 4 || i == 12 || i == 21) continue;
        char c = ident_a.fingerprint[i];
        assert((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'));
    }

    /* Challenge/response: the right secret and nonce verify. */
    uint8_t nonce[32], received[32], expected_mac[32];
    memset(nonce, 0x42, sizeof(nonce));
    assert(aweos_netid_respond(secret_a, nonce, sizeof(nonce), ident_a.id, received) == AWEOS_OK);
    assert(aweos_netid_respond(secret_a, nonce, sizeof(nonce), ident_a.id, expected_mac) == AWEOS_OK);
    assert(memcmp(received, expected_mac, 32) == 0);
    assert(aweos_netid_mac_equal(received, expected_mac) == AWEOS_OK);

    /* Reject: tampered MAC. */
    uint8_t tampered[32];
    memcpy(tampered, expected_mac, 32);
    tampered[0] ^= 0x01;
    assert(aweos_netid_mac_equal(received, tampered) == AWEOS_ERR_VERIFY);

    /* Reject: wrong nonce in the transcript. */
    uint8_t other_nonce[32];
    memcpy(other_nonce, nonce, sizeof(other_nonce));
    other_nonce[31] ^= 0x08;
    uint8_t wrong_nonce_mac[32];
    assert(aweos_netid_respond(secret_a, other_nonce, sizeof(other_nonce), ident_a.id, wrong_nonce_mac) == AWEOS_OK);
    assert(aweos_netid_mac_equal(received, wrong_nonce_mac) == AWEOS_ERR_VERIFY);

    /* Reject: a different device identity and secret cannot impersonate. */
    uint8_t spoofed_mac[32];
    assert(aweos_netid_respond(secret_b, nonce, sizeof(nonce), ident_b.id, spoofed_mac) == AWEOS_OK);
    assert(aweos_netid_mac_equal(received, spoofed_mac) == AWEOS_ERR_VERIFY);

    /* Reject: nonce longer than the declared handshake bound. */
    uint8_t oversized_nonce[AWEOS_NETID_MAX_NONCE + 1U];
    memset(oversized_nonce, 0, sizeof(oversized_nonce));
    assert(aweos_netid_respond(secret_a, oversized_nonce, sizeof(oversized_nonce), ident_a.id, expected_mac)
           == AWEOS_ERR_INVALID_PARAM);

    /* Fail-closed parameter validation. */
    assert(aweos_netid_respond(secret_a, nonce, sizeof(nonce), NULL, expected_mac) == AWEOS_ERR_INVALID_PARAM);
    assert(aweos_netid_derive(NULL, &ident_a) == AWEOS_ERR_INVALID_PARAM);
    assert(aweos_netid_sha256(NULL, 5, digest_a) == AWEOS_ERR_INVALID_PARAM);
    assert(aweos_netid_mac_equal(NULL, expected_mac) == AWEOS_ERR_INVALID_PARAM);

    puts("PASS: device identity SHA-256 vectors, HMAC vector, deterministic derivation, fingerprint format, challenge/response accept and fail-closed rejection.");
    return 0;
}
C_TEST

cc -std=c11 -Wall -Wextra -Werror \
    -I"$repo_root/src/core" \
    "$repo_root/src/core/netid.c" netid_test.c -o netid_test
./netid_test
