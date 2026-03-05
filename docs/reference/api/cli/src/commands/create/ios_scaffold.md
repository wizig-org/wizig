# `cli/src/commands/create/ios_scaffold.zig`

_Language: Zig_

iOS host scaffold generation.

This module materializes the iOS template tree and performs token/path
substitution for app naming while preserving deterministic seed layout.

## Public API

### `createIos` (fn)

Creates the iOS host scaffold from bundled templates.

The generated project is immediately buildable using `xcodebuild` and uses
a path-token rewrite for seed placeholders such as `__APP_NAME__`.

```zig
pub fn createIos(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    templates_root: []const u8,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    force_host_overwrite: bool,
) !void {
```
