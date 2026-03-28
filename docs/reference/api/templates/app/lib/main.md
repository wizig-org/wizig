# `templates/app/lib/main.zig`

_Language: Zig_

Template Zig module scaffolded into new Wizig apps.

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

### `echoZig` (fn)

No declaration docs available.

```zig
pub fn echoZig(input: []const u8) void {
```
