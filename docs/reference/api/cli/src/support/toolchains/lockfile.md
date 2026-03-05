# `cli/src/support/toolchains/lockfile.zig`

_Language: Zig_

Toolchain lock-file generation.

`wizig create` writes `.wizig/toolchain.lock.json` to capture the manifest
hash and detected host tool versions at scaffold time.

## Public API

### `writeProjectLock` (fn)

Probes host tools and writes project lock metadata JSON.

The emitted file is intentionally deterministic for a given manifest and
probe result set, except for creation timestamp.

```zig
pub fn writeProjectLock(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    manifest: types.ToolchainsManifest,
) !void {
```
