# `cli/src/support/sdk_locator.zig`

_Language: Zig_

SDK/runtime/template locator for portable Wizig installs.

## Public API

### `ResolvedSdk` (const)

Resolved directories required to scaffold and run projects.

```zig
pub const ResolvedSdk = struct {
```

### `resolve` (fn)

Resolves Wizig SDK roots using CLI/env/install/dev fallback precedence.

```zig
pub fn resolve(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    explicit_root: ?[]const u8,
) !ResolvedSdk {
```
