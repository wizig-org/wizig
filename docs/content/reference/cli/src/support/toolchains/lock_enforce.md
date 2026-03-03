# `cli/src/support/toolchains/lock_enforce.zig`

_Language: Zig_

Toolchain lock-file enforcement for run/codegen commands.

This module validates `.wizig/toolchain.lock.json` (when present) against
the current host environment. It intentionally checks policy minima from the
lock payload so commands fail fast when host tooling drifts below the locked
requirements used at scaffold time.

## Public API

### `enforceProjectLock` (fn)

Enforces project lock policy unless explicitly bypassed.

```zig
pub fn enforceProjectLock(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    allow_toolchain_drift: bool,
) !void {
```
