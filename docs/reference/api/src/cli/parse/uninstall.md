# `src/cli/parse/uninstall.zig`

_Language: Zig_

`wizig uninstall` clap-backed argument parsing.

## Public API

### `UninstallOptions` (const)

No declaration docs available.

```zig
pub const UninstallOptions = struct {
```

### `parseUninstallOptions` (fn)

Parses `wizig uninstall` flags or returns `null` for `--help`.

```zig
pub fn parseUninstallOptions(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?UninstallOptions {
```
