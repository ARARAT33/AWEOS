#ifndef AWEOS_NETID_H
#define AWEOS_NETID_H

#include "types.h"

#include <stddef.h>
#include <stdint.h>

/*
 * AWEOS Device Identity Manager (Network Platform, module 2).
 *
 * This module derives a stable 32-byte identifier from a 32-byte secret
 * and exposes SHA-256/HMAC-SHA256 primitives. The caller is responsible for
 * obtaining the secret from a cryptographically secure source and protecting
 * it at rest. No personal data is embedded in the derived identifier.
 *
 * IMPORTANT: aweos_netid_respond() only computes a keyed MAC. A remote peer
 * cannot verify that MAC from the public identifier alone; this API does not
 * implement public-key authentication, key enrollment, or a remote verifier.
 * Do not use it as a network authentication protocol without a separately
 * designed and reviewed shared-key trust model.
 */

#define AWEOS_NETID_SECRET_LEN 32
#define AWEOS_NETID_ID_LEN 32
#define AWEOS_NETID_MAC_LEN 32
#define AWEOS_NETID_FINGERPRINT_LEN 31 /* AWE-XXXXXXXX-XXXXXXXX-XXXXXXXX plus NUL */
#define AWEOS_NETID_MAX_NONCE 64
#define AWEOS_SHA256_BLOCK_LEN 64U
#define AWEOS_SHA256_OUT_LEN 32U

/* Incremental SHA-256 context for payloads that must not be fully
 * buffered in memory. No dynamic allocation is used by the implementation. */
typedef struct {
    uint32_t state[8];
    uint8_t buffer[AWEOS_SHA256_BLOCK_LEN];
    size_t buffered;
    uint64_t total_len;
} aweos_sha256_ctx_t;

typedef struct {
    uint8_t id[AWEOS_NETID_ID_LEN];
    char fingerprint[AWEOS_NETID_FINGERPRINT_LEN];
} aweos_device_identity_t;

/* NIST FIPS 180-4 SHA-256. Returns AWEOS_OK or AWEOS_ERR_INVALID_PARAM. */
int aweos_netid_sha256(const uint8_t *data, size_t len, uint8_t out[AWEOS_NETID_ID_LEN]);

/* Incremental SHA-256: hash chunks in order, then finalize. */
void aweos_netid_sha256_init(aweos_sha256_ctx_t *ctx);
void aweos_netid_sha256_update(aweos_sha256_ctx_t *ctx, const uint8_t *data, size_t len);
void aweos_netid_sha256_final(aweos_sha256_ctx_t *ctx, uint8_t out[AWEOS_SHA256_OUT_LEN]);

/* RFC 2104 HMAC-SHA256. Keys longer than the block size are hashed first. */
int aweos_netid_hmac_sha256(const uint8_t *key, size_t key_len,
                            const uint8_t *msg, size_t msg_len,
                            uint8_t out[AWEOS_NETID_MAC_LEN]);

/* Derive the public device identity from the 32-byte device secret. */
int aweos_netid_derive(const uint8_t secret[AWEOS_NETID_SECRET_LEN],
                       aweos_device_identity_t *identity);

/* Compute HMAC(secret, label || id || nonce). This returns a tag only;
 * it is not publicly verifiable without a separately provisioned shared key.
 * Oversized nonces are rejected and no dynamic allocation is performed. */
int aweos_netid_respond(const uint8_t secret[AWEOS_NETID_SECRET_LEN],
                        const uint8_t *nonce, size_t nonce_len,
                        const uint8_t id[AWEOS_NETID_ID_LEN],
                        uint8_t out_mac[AWEOS_NETID_MAC_LEN]);

/* Constant-time MAC comparison; never short-circuits on the first difference. */
int aweos_netid_mac_equal(const uint8_t a[AWEOS_NETID_MAC_LEN],
                          const uint8_t b[AWEOS_NETID_MAC_LEN]);

#endif /* AWEOS_NETID_H */
