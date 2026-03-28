# `src/cli/run/platform/options_parse.zig`

_Language: Zig_

clap-backed parsing for platform-specific run options.

## Public API

### `parseRunOptions` (fn)

Parses CLI arguments into validated platform run options.

```zig
pub fn parseRunOptions(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?types.RunOptions {
```
