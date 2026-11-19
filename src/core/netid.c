#include "netid.h"

#include <string.h>

#define SHA256_BLOCK_LEN 64U
#define SHA256_OUT_LEN 32U

static const uint8_t NETID_DOMAIN_BYTES[] = "AWEOS-NETID-V1";
enum { NETID_DOMAIN_LEN = sizeof(NETID_DOMAIN_BYTES) - 1U };

static uint32_t sha256_rotr(uint32_t value, unsigned bits) {
    return (value >> bits) | (value << (32U - bits));
}

void aweos_netid_sha256_init(aweos_sha256_ctx_t *ctx) {
    static const uint32_t H0[8] = {
        0x6A09E667U, 0xBB67AE85U, 0x3C6EF372U, 0xA54FF53AU,
        0x510E527FU, 0x9B05688CU, 0x1F83D9ABU, 0x5BE0CD19U
    };
    memcpy(ctx->state, H0, sizeof(H0));
    ctx->buffered = 0;
    ctx->total_len = 0;
}

static const uint32_t K[64] = {
    0x428A2F98U, 0x71374491U, 0xB5C0FBCFU, 0xE9B5DBA5U,
    0x3956C25BU, 0x59F111F1U, 0x923F82A4U, 0xAB1C5ED5U,
    0xD807AA98U, 0x12835B01U, 0x243185BEU, 0x550C7DC3U,
    0x72BE5D74U, 0x80DEB1FEU, 0x9BDC06A7U, 0xC19BF174U,
    0xE49B69C1U, 0xEFBE4786U, 0x0FC19DC6U, 0x240CA1CCU,
    0x2DE92C6FU, 0x4A7484AAU, 0x5CB0A9DCU, 0x76F988DAU,
    0x983E5152U, 0xA831C66DU, 0xB00327C8U, 0xBF597FC7U,
    0xC6E00BF3U, 0xD5A79147U, 0x06CA6351U, 0x14292967U,
    0x27B70A85U, 0x2E1B2138U, 0x4D2C6DFCU, 0x53380D13U,
    0x650A7354U, 0x766A0ABBU, 0x81C2C92EU, 0x92722C85U,
    0xA2BFE8A1U, 0xA81A664BU, 0xC24B8B70U, 0xC76C51A3U,
    0xD192E819U, 0xD6990624U, 0xF40E3585U, 0x106AA070U,
    0x19A4C116U, 0x1E376C08U, 0x2748774CU, 0x34B0BCB5U,
    0x391C0CB3U, 0x4ED8AA4AU, 0x5B9CCA4FU, 0x682E6FF3U,
    0x748F82EEU, 0x78A5636FU, 0x84C87814U, 0x8CC70208U,
    0x90BEFFFAU, 0xA4506CEBU, 0xBEF9A3F7U, 0xC67178F2U
};

static void aweos_netid_sha256_compress(aweos_sha256_ctx_t *ctx, const uint8_t block[SHA256_BLOCK_LEN]) {
    uint32_t w[64];
    for (unsigned i = 0; i < 16U; ++i) {
        w[i] = ((uint32_t)block[4U * i] << 24U) |
               ((uint32_t)block[4U * i + 1U] << 16U) |
               ((uint32_t)block[4U * i + 2U] << 8U) |
               (uint32_t)block[4U * i + 3U];
    }
    for (unsigned i = 16U; i < 64U; ++i) {
        uint32_t s0 = sha256_rotr(w[i - 15U], 7) ^ sha256_rotr(w[i - 15U], 18) ^ (w[i - 15U] >> 3);
        uint32_t s1 = sha256_rotr(w[i - 2U], 17) ^ sha256_rotr(w[i - 2U], 19) ^ (w[i - 2U] >> 10);
        w[i] = w[i - 16U] + s0 + w[i - 7U] + s1;
    }

    uint32_t a = ctx->state[0], b = ctx->state[1], c = ctx->state[2], d = ctx->state[3];
    uint32_t e = ctx->state[4], f = ctx->state[5], g = ctx->state[6], h = ctx->state[7];

    for (unsigned i = 0; i < 64U; ++i) {
        uint32_t s1 = sha256_rotr(e, 6) ^ sha256_rotr(e, 11) ^ sha256_rotr(e, 25);
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t t1 = h + s1 + ch + K[i] + w[i];
        uint32_t s0 = sha256_rotr(a, 2) ^ sha256_rotr(a, 13) ^ sha256_rotr(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = s0 + maj;
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }

    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
    ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

void aweos_netid_sha256_update(aweos_sha256_ctx_t *ctx, const uint8_t *data, size_t len) {
    ctx->total_len += (uint64_t)len;
    while (len > 0) {
        size_t take = SHA256_BLOCK_LEN - ctx->buffered;
        if (take > len) take = len;
        memcpy(&ctx->buffer[ctx->buffered], data, take);
        ctx->buffered += take;
        data += take;
        len -= take;
        if (ctx->buffered == SHA256_BLOCK_LEN) {
            aweos_netid_sha256_compress(ctx, ctx->buffer);
            ctx->buffered = 0;
        }
    }
}

void aweos_netid_sha256_final(aweos_sha256_ctx_t *ctx, uint8_t out[SHA256_OUT_LEN]) {
    uint64_t bits = ctx->total_len * 8U;
    uint8_t pad = 0x80;
    aweos_netid_sha256_update(ctx, &pad, 1);
    uint8_t zero = 0;
    while (ctx->buffered != 56U) {
        aweos_netid_sha256_update(ctx, &zero, 1);
    }
    uint8_t length_bytes[8];
    for (unsigned i = 0; i < 8U; ++i) {
        length_bytes[i] = (uint8_t)(bits >> (56U - 8U * i));
    }
    /* total_len bookkeeping no longer matters past this point. */
    for (unsigned i = 0; i < 8U; ++i) {
        ctx->buffer[56U + i] = length_bytes[i];
    }
    aweos_netid_sha256_compress(ctx, ctx->buffer);
    ctx->buffered = 0;
    for (unsigned i = 0; i < 8U; ++i) {
        out[4U * i] = (uint8_t)(ctx->state[i] >> 24);
        out[4U * i + 1U] = (uint8_t)(ctx->state[i] >> 16);
        out[4U * i + 2U] = (uint8_t)(ctx->state[i] >> 8);
        out[4U * i + 3U] = (uint8_t)(ctx->state[i]);
    }
}

int aweos_netid_sha256(const uint8_t *data, size_t len, uint8_t out[SHA256_OUT_LEN]) {
    if ((!data && len > 0) || !out) return AWEOS_ERR_INVALID_PARAM;
    aweos_sha256_ctx_t ctx;
    aweos_netid_sha256_init(&ctx);
    if (data && len > 0) aweos_netid_sha256_update(&ctx, data, len);
    aweos_netid_sha256_final(&ctx, out);
    return AWEOS_OK;
}

int aweos_netid_hmac_sha256(const uint8_t *key, size_t key_len,
                            const uint8_t *msg, size_t msg_len,
                            uint8_t out[SHA256_OUT_LEN]) {
    if ((!key && key_len > 0) || (!msg && msg_len > 0) || !out) return AWEOS_ERR_INVALID_PARAM;

    uint8_t block[SHA256_BLOCK_LEN];
    memset(block, 0x36, sizeof(block)); /* ipad */
    uint8_t hashed_key[SHA256_OUT_LEN];
    if (key_len > SHA256_BLOCK_LEN) {
        int rc = aweos_netid_sha256(key, key_len, hashed_key);
        if (rc != AWEOS_OK) return rc;
        for (size_t i = 0; i < sizeof(hashed_key); ++i) block[i] ^= hashed_key[i];
    } else {
        for (size_t i = 0; i < key_len; ++i) block[i] ^= key[i];
    }

    aweos_sha256_ctx_t inner;
    aweos_netid_sha256_init(&inner);
    aweos_netid_sha256_update(&inner, block, sizeof(block));
    if (msg && msg_len > 0) aweos_netid_sha256_update(&inner, msg, msg_len);
    uint8_t inner_digest[SHA256_OUT_LEN];
    aweos_netid_sha256_final(&inner, inner_digest);

    memset(block, 0x5C, sizeof(block)); /* opad */
    if (key_len > SHA256_BLOCK_LEN) {
        for (size_t i = 0; i < sizeof(hashed_key); ++i) block[i] ^= hashed_key[i];
    } else {
        for (size_t i = 0; i < key_len; ++i) block[i] ^= key[i];
    }

    aweos_sha256_ctx_t outer;
    aweos_netid_sha256_init(&outer);
    aweos_netid_sha256_update(&outer, block, sizeof(block));
    aweos_netid_sha256_update(&outer, inner_digest, sizeof(inner_digest));
    aweos_netid_sha256_final(&outer, out);
    return AWEOS_OK;
}

static void hex_nibble_encode(char *dst, const uint8_t *bytes, size_t byte_count) {
    static const char hex_digits[16] = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
    };
    for (size_t i = 0; i < byte_count; ++i) {
        dst[2U * i] = hex_digits[(bytes[i] >> 4) & 0x0FU];
        dst[2U * i + 1U] = hex_digits[bytes[i] & 0x0FU];
    }
}

int aweos_netid_derive(const uint8_t secret[AWEOS_NETID_SECRET_LEN],
                       aweos_device_identity_t *identity) {
    if (!secret || !identity) return AWEOS_ERR_INVALID_PARAM;

    /* id = SHA-256(domain || secret): the domain binds the id to this
       protocol version, so the same raw secret derives different values
       if later protocol revisions change labels. */
    uint8_t input[NETID_DOMAIN_LEN + AWEOS_NETID_SECRET_LEN];
    memcpy(input, NETID_DOMAIN_BYTES, NETID_DOMAIN_LEN);
    memcpy(&input[NETID_DOMAIN_LEN], secret, AWEOS_NETID_SECRET_LEN);
    int rc = aweos_netid_sha256(input, sizeof(input), identity->id);
    if (rc != AWEOS_OK) return rc;

    /* Human-readable fingerprint from the first 10 id bytes: AWE-XXXXXXXX-XXXXXXXX-XXXXXXXX */
    identity->fingerprint[0] = 'A';
    identity->fingerprint[1] = 'W';
    identity->fingerprint[2] = 'E';
    identity->fingerprint[3] = '-';
    size_t offset = 4;
    for (unsigned group = 0; group < 3U; ++group) {
        hex_nibble_encode(&identity->fingerprint[offset], &identity->id[4U * group], 4U);
        offset += 8U;
        if (group != 2U) identity->fingerprint[offset++] = '-';
    }
    identity->fingerprint[offset] = '\0';
    if (offset != 30U) return AWEOS_ERR_VERIFY;
    return AWEOS_OK;
}

int aweos_netid_respond(const uint8_t secret[AWEOS_NETID_SECRET_LEN],
                        const uint8_t *nonce, size_t nonce_len,
                        const uint8_t id[AWEOS_NETID_ID_LEN],
                        uint8_t out_mac[AWEOS_NETID_MAC_LEN]) {
    if (!secret || (!nonce && nonce_len > 0) || !id || !out_mac) return AWEOS_ERR_INVALID_PARAM;
    if (nonce_len > AWEOS_NETID_MAX_NONCE) return AWEOS_ERR_INVALID_PARAM;

    /* HMAC key = device secret; message = domain || id || nonce. */
    uint8_t msg[NETID_DOMAIN_LEN + AWEOS_NETID_ID_LEN + AWEOS_NETID_MAX_NONCE];
    size_t offset = 0;
    memcpy(&msg[offset], NETID_DOMAIN_BYTES, NETID_DOMAIN_LEN);
    offset += NETID_DOMAIN_LEN;
    memcpy(&msg[offset], id, AWEOS_NETID_ID_LEN);
    offset += AWEOS_NETID_ID_LEN;
    if (nonce_len > 0) {
        memcpy(&msg[offset], nonce, nonce_len);
        offset += nonce_len;
    }
    return aweos_netid_hmac_sha256(secret, AWEOS_NETID_SECRET_LEN, msg, offset, out_mac);
}

int aweos_netid_mac_equal(const uint8_t a[AWEOS_NETID_MAC_LEN],
                          const uint8_t b[AWEOS_NETID_MAC_LEN]) {
    if (!a || !b) return AWEOS_ERR_INVALID_PARAM;
    volatile uint8_t diff = 0;
    for (unsigned i = 0; i < AWEOS_NETID_MAC_LEN; ++i) {
        diff |= (uint8_t)(a[i] ^ b[i]);
    }
    return diff == 0 ? AWEOS_OK : AWEOS_ERR_VERIFY;
}
