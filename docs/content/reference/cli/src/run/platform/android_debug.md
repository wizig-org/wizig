# `cli/src/run/platform/android_debug.zig`

_Language: Zig_

Android debugger and log-monitor attachment helpers.

This module handles jdb attachment setup and PID/JDWP polling used by both
debugger and filtered logcat execution paths.

## Public API

### `attachJdb` (fn)

Attaches `jdb` to the target Android app via adb JDWP forwarding.

```zig
pub fn attachJdb(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    serial: []const u8,
    app_id: []const u8,
) !void {
```

### `waitForAndroidPid` (fn)

Waits for an Android app PID to become visible via `pidof`.

```zig
pub fn waitForAndroidPid(
    io: std.Io,
    stderr: *Io.Writer,
    serial: []const u8,
    app_id: []const u8,
) !u32 {
```
