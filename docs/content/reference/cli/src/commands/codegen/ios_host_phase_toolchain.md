# `cli/src/commands/codegen/ios_host_phase_toolchain.zig`

_Language: Zig_

Shared shell-script snippets for deterministic iOS Zig toolchain selection.

This module keeps the main build-phase template focused on orchestration
while encapsulating lock-based Zig resolution and optional auto-install.

## Public API

### `resolve_zig` (const)

Resolves `ZIG_BIN` deterministically from lock metadata.

Behavior:
- Reads `.wizig/toolchain.lock.json` for zig detected/min version.
- Prefers explicit `ZIG_BINARY`, then cached lock-pinned installs.
- Supports opt-in network install (`WIZIG_ZIG_AUTO_INSTALL=1`).
- Enforces lock version minimum unless drift override is explicitly set.

```zig
pub const resolve_zig =
```
