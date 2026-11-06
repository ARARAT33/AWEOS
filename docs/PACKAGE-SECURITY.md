# AWEOS package security status

The rootfs installs `scripts/awepkg.sh` as `/usr/bin/awepkg`. The current
`.awe` format is a gzip tar with one `manifest.meta` and optional `root/`
payload.

Implemented safeguards include conservative package/path validation, archive
entry-type rejection, no-overwrite preflight, symlink-parent rejection,
same-directory staging and no-overwrite publication, rollback of files created
by a failed transaction, SHA-256 ownership records, and hash-checked removal
that preserves modified files. Installed modes are normalized to 0755 for
executables and 0644 for data; package-supplied setuid/setgid/sticky and
group/world-writable bits are not retained. The package database is constrained
to the selected `AWEPKG_ROOT`.

## Unsigned packages

The current archive format has no authenticated publisher signature or trusted
keyring. A post-install SHA-256 detects later local modification; it does not
authenticate the publisher or the package before installation. Therefore
`awepkg install` refuses unsigned packages by default. The explicit
`AWEPKG_ALLOW_UNSIGNED=1` override is for trusted development tests only and
must not be used for production or untrusted packages.

A production format still needs a versioned signed manifest, trust/key rotation,
signature verification before extraction, bounded archive/file-count limits,
dependency resolution, and a sandbox/permission model. These are not claimed.

## Legacy C AOSIN v1

The previous C implementation wrote a fabricated 1 KiB payload, supplied the
empty-file SHA-256, and treated a magic number as verification. It did not
deploy or remove payloads. Its public API now returns explicit errors without
touching output files, target roots, or package metadata until a real payload
format, authenticated manifest, and atomic deployment backend exist.

`make test-shell` and the dedicated package-safety workflow run the shell
package integration test and the C AOSIN fail-closed regression with
AddressSanitizer and UndefinedBehaviorSanitizer.


## Target BusyBox compatibility

The package integration test also reruns install/remove/rollback cases through
BusyBox `ash` and BusyBox applets. The rootfs validator requires executable
`/usr/bin/awepkg` and checks that every BusyBox applet used by the package
manager is present in the actual target BusyBox binary. This catches
host-only GNU utility assumptions before an image is considered valid.
