# `templates/app/lib/main.zig`

Template Zig module scaffolded into new Ziggy apps.

## Public API

### `appName` (fn)

Returns the application name configured at scaffold time.

```zig
pub fn appName() []const u8 {
```

### `echo` (fn)

Echo helper used by host examples and smoke tests.

```zig
pub fn echo(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
```
