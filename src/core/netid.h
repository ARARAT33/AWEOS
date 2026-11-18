#ifndef AWEOS_NETID_H
#define AWEOS_NETID_H

#include "types.h"

#include <stddef.h>
#include <stdint.h>

/*
 * AWEOS Device Identity Manager (Network Platform, module 2).
 *
 * Every AWEOS device owns a 32-byte secret. The secret never leaves the
 * device; peers only see the derived 32-byte device id and can challenge the
 * device with a nonce that must be answered with an HMAC-SHA256 tag. No
 * personal data is embedded in the identity: the id is a hash of the secret
 * under a versioned domain-separation label.
 */

#define AWEOS_NETID_SECRET_LEN 32
#define AWEOS_NETID_ID_LEN 32
#define AWEOS_NETID_MAC_LEN 32
#define AWEOS_NETID_FINGERPRINT_LEN 31 /* AWE-XXXXXXXX-XXXXXXXX-XXXXXXXX plus NUL */
#define AWEOS_NETID_MAX_NONCE 64

typedef struct {
    uint8_t id[AWEOS_NETID_ID_LEN];
    char fingerprint[AWEOS_NETID_FINGERPRINT_LEN];
} aweos_device_identity_t;

/* NIST FIPS 180-4 SHA-256. Returns AWEOS_OK or AWEOS_ERR_INVALID_PARAM. */
int aweos_netid_sha256(const uint8_t *data, size_t len, uint8_t out[AWEOS_NETID_ID_LEN]);

/* RFC 2104 HMAC-SHA256. Keys longer than the block size are hashed first. */
int aweos_netid_hmac_sha256(const uint8_t *key, size_t key_len,
                            const uint8_t *msg, size_t msg_len,
                            uint8_t out[AWEOS_NETID_MAC_LEN]);

/* Derive the public device identity from the 32-byte device secret. */
int aweos_netid_derive(const uint8_t secret[AWEOS_NETID_SECRET_LEN],
                       aweos_device_identity_t *identity);

/* Answer a challenge: HMAC(secret, label || id || nonce).
 * Nonces longer than AWEOS_NETID_MAX_NONCE bytes are rejected intentionally:
 * callers must keep handshake values small, and the module must not allocate. */
int aweos_netid_respond(const uint8_t secret[AWEOS_NETID_SECRET_LEN],
                        const uint8_t *nonce, size_t nonce_len,
                        const uint8_t id[AWEOS_NETID_ID_LEN],
                        uint8_t out_mac[AWEOS_NETID_MAC_LEN]);

/* Constant-time MAC comparison; never short-circuits on the first difference. */
int aweos_netid_mac_equal(const uint8_t a[AWEOS_NETID_MAC_LEN],
                          const uint8_t b[AWEOS_NETID_MAC_LEN]);

#endif /* AWEOS_NETID_H */
