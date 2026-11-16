

## 2026-11-16 run 2 — AYUI IPC security hardening

### Work continued from
- PR #57 branch `fix/qemu-serial-debug-diagnostics-20261116` head `1d437713`.
- CI inspected before this run: Userland Validation run #583 **PASS**; full image/boot runs #645-#648 **FAIL**. The exact #648 failure step could not be read because the GitHub REST API is rate-limited from this environment and the Actions run page requires JavaScript; the BIOS diagnostic artifacts from run #648 still need to be downloaded and inspected next run.

### Critical issue addressed (from the 2026-11-14 audit, item 3)
- The AYUI IPC socket lived at `/tmp/aweui-ipc.sock`, a world-writable directory.
- `IpcServer::new` unconditionally deleted whatever occupied the socket path, so a local attacker could place a directory or unrelated file there and have it destroyed, or race the deletion.
- The server never authenticated peers, while the request API includes `LaunchCommand` and `PowerAction`, and the compositor currently runs as root from PID 1.

### Changes on `fix/ayui-ipc-hardening-20261116` (stacked on PR #57)
- `AWEUI/src/ipc.rs`:
  - New `resolve_socket_path`/`default_socket_path`: the socket now lives in `$XDG_RUNTIME_DIR` or `/run/user/<uid>`, never in `/tmp`.
  - The runtime directory is created with mode `0700`; the socket is bound and then set to mode `0600`.
  - Stale-socket cleanup is fail-closed: only a real socket is removed; a non-socket object at the path aborts construction instead of being deleted.
  - Every accepted connection is checked with `SO_PEERCRED` (`nix` `PeerCredentials`, already a dependency); connections from a different uid are rejected before any request is parsed.
  - New `IpcServer::bind` separates binding from the listener thread so permissions are testable.
  - Added unit tests: runtime-dir path resolution (explicit, empty, and fallback cases), stale-socket removal, refusal to delete a non-socket path, and owner-only socket permissions.
- `AWEUI/src/state.rs`: construct the IPC server with the hardened default socket path.
- No files under `/linux` were modified. No installer, disk, partition, updater, or user-data behavior changed. The request API and wire format are unchanged, so existing AYUI clients remain compatible.

### Known remaining gaps (not fixed in this run)
- The compositor still runs as root when launched from PID 1 in the current rootfs init; the IPC hardening limits exposure but the session-user split is still required.
- `LaunchCommand`/`PowerAction` remain available to any same-uid process; a fuller authorization model is still open.
- The unsigned `awepkg install` path and the dummy AOSIN payload remain critical blockers.

### Validation status
- The Rust unit tests run in CI via `cargo test --workspace` in the Userland Validation workflow on this branch; results must be inspected before any pass is claimed.
- No local Rust toolchain exists in this connector-only environment.

### Next run priorities
1. Inspect this branch's Userland Validation and full image/boot results.
2. Download and read the BIOS diagnostic artifacts from PR #57 run #648 (serial + `qemu-bios-debug.log`) and identify the first failing boot stage.
3. Continue the privilege split: run the AYUI session as an unprivileged user in the rootfs init.
4. Then address the unsigned package-installation path.
