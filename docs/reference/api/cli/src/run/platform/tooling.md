# `cli/src/run/platform/tooling.zig`

_Language: Zig_

Toolchain command discovery helpers.

These helpers provide lightweight capability checks used to validate
debugger/tool availability before entering platform-specific flows.

## Public API

### `commandExists` (fn)

Returns true when `command_name` is discoverable via `which`.

```zig
pub fn commandExists(
    arena: std.mem.Allocator,
    io: std.Io,
    command_name: []const u8,
) bool {
```
