# `cli/src/commands/create/toolchain_lock.zig`

_Language: Zig_

Toolchain lock-file creation for `wizig create`.

This module bridges scaffold creation with centralized toolchain governance
by loading manifest policy and writing `.wizig/toolchain.lock.json`.

## Public API

### `writeProjectLock` (fn)

Writes a project lock file using policy from the resolved SDK/workspace root.

This step runs after scaffold+codegen so generated projects always include
a reproducibility marker tied to the manifest and host tool versions.

```zig
pub fn writeProjectLock(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    sdk_root: []const u8,
    project_root: []const u8,
) !void {
```
