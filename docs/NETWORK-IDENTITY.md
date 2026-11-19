# AWEOS Device Identity Manager (Network Platform module 2)

Status: C cryptographic primitives and deterministic identity derivation are implemented; not yet integrated into any network daemon or AYUI surface. The module is not a complete device-authentication protocol. Do not describe AWEOS as having end-to-end device networking until key provisioning, verifiable peer authentication, the connection manager, and service discovery are implemented and tested.

## What exists today

- `src/core/netid.h` / `src/core/netid.c`: a self-contained SHA-256 (FIPS
  180-4) and HMAC-SHA256 (RFC 2104) implementation plus the identity API:
  - `aweos_netid_sha256`
  - `aweos_netid_hmac_sha256`
  - `aweos_netid_derive`: derives the 32-byte public device id and the
    human-readable `AWE-XXXXXXXX-XXXXXXXX-XXXXXXXX` fingerprint from the
    32-byte device secret under the versioned label `AWEOS-NETID-V1`.
  - `aweos_netid_respond`: computes a response tag using
    HMAC(secret, "AWEOS-NETID-V1" || device_id || nonce). It does not expose
    the secret and embeds no personal data in the id. The API only computes
    the tag; it does not provide a remote verifier.
  - `aweos_netid_mac_equal`: constant-time MAC comparison.
- `scripts/test-netid.sh`: compiles the module with
  `cc -std=c11 -Wall -Wextra -Werror` and checks FIPS 180-4 SHA-256 vectors
  ("", "abc", the two-block FIPS message), RFC 4231 Test Case 1, deterministic
  derivation, distinct secrets producing distinct identities, fingerprint
  format, challenge/response acceptance, and fail-closed rejection of tampered
  MACs, wrong nonces, foreign identities and oversized nonces.
- Wired into `make test-shell`.

## Security boundary and authentication limitation

The current challenge-response helper is **not sufficient for remote peer
authentication**. HMAC verification requires the same secret (or an equivalent
shared key) on the verifying side. The public device identifier is a hash and
does not let another device verify the HMAC. This repository does not yet
implement a public-key signature, peer-verification API, enrollment protocol,
or secure secret provisioning. Do not use the returned tag as proof of device
identity or authorize remote services from it.

Before network integration, select a reviewed asymmetric authentication
design and a vetted cryptographic implementation, generate private material
from the operating-system CSPRNG, define protected storage/rotation/revocation,
and add independent known-answer and negative tests. The current SHA-256 and
HMAC implementation has not received an independent cryptographic audit.

## Design constraints honored

- No dynamic allocation: bounded nonce length (`AWEOS_NETID_MAX_NONCE`).
- Fail closed: invalid parameters and oversized nonces are errors, never
  empty tolerations.
- No secrets or keys are stored, printed, or logged anywhere in the module;
  the test secret constants are fixture values inside the test only.
- The module is vendor-neutral and has no external dependencies.

## Next integration steps

1. Secret provisioning: a supervisor-owned shadow file with 0600 permissions
   and an explicit on-disk format review before any device enrollment exists.
2. Connection Manager (module 4) on top of this identity: peers prove
   possession of the secret by responding to per-connection nonces.
3. Service Discovery Engine (module 3) must derive advisory names from the
   id, never from hostname, MAC address, or user names.
