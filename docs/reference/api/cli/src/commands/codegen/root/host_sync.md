# `cli/src/commands/codegen/root/host_sync.zig`

_Language: Zig_

Host-project patching and SDK mirror synchronization after generation.

## Public API

### `SyncResult` (const)

Post-generation sync results for patched host projects.

```zig
pub const SyncResult = struct {
```

### `syncHosts` (fn)

Mirrors generated host support artifacts and patches host projects when needed.

```zig
pub fn syncHosts(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    spec: api.ApiSpec,
) !SyncResult {
```
