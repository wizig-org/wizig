# `cli/src/run/platform/android_log_stream.zig`

_Language: Zig_

Android run helper functions for preselected devices and log streaming.

## Public API

### `resolvePreselectedAndroidDevice` (fn)

Resolves a preselected Android device when unified run already chose target.

```zig
pub fn resolvePreselectedAndroidDevice(
    arena: std.mem.Allocator,
    stderr: *Io.Writer,
    selector: ?[]const u8,
) !types.AndroidDevice {
```

### `streamAndroidLogs` (fn)

Streams Android logs with liveness + timeout watchdog semantics.

```zig
pub fn streamAndroidLogs(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    serial: []const u8,
    app_id: []const u8,
    monitor_timeout_seconds: ?u64,
) !void {
```
