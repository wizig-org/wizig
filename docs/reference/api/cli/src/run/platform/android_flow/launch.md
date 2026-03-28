# `cli/src/run/platform/android_flow/launch.zig`

_Language: Zig_

Android install, launch, debugger, and log-monitor attachment.

This module owns the final run step after the APK has been built and the
launch metadata has been resolved.

## Public API

### `launchAndroidApp` (fn)

Installs the APK, launches the app, and attaches the requested monitor.

```zig
pub fn launchAndroidApp(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    serial: []const u8,
    apk: []const u8,
    launch_metadata: metadata.AndroidLaunchMetadata,
    debugger_mode: types.DebuggerMode,
    once: bool,
    monitor_timeout_seconds: ?u64,
) !void {
```
