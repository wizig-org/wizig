# `core/src/runtime.zig`

Minimal runtime object used by generated host bindings.

## Public API

### `Runtime` (const)

Runtime holds app-level metadata and provides simple sample methods.

```zig
pub const Runtime = struct {
```

### `init` (fn)

Allocates and initializes a runtime instance for `app_name`.

```zig
    pub fn init(allocator: std.mem.Allocator, app_name: []const u8) !Runtime {
```

### `deinit` (fn)

Releases owned runtime resources.

```zig
    pub fn deinit(self: *Runtime) void {
```

### `echo` (fn)

Returns a formatted string prefixing input with the app name.

```zig
    pub fn echo(self: *const Runtime, input: []const u8, allocator: std.mem.Allocator) ![]u8 {
```
