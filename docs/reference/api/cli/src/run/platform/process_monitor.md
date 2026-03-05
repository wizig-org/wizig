# `cli/src/run/platform/process_monitor.zig`

_Language: Zig_

Watchdog-controlled inherited monitor execution.

This module owns long-running monitor behavior (timeout and app-liveness
driven shutdown) so the main process supervisor remains focused on generic
command execution.

## Public API

### `MonitorCommandSpec` (const)

Monitor command invocation parameters.

```zig
pub const MonitorCommandSpec = struct {
```

### `LivenessProbe` (const)

App liveness probe settings used by monitor watchdog execution.

```zig
pub const LivenessProbe = struct {
```

### `MonitorWatchdog` (const)

Watchdog controls for long-running monitor commands.

```zig
pub const MonitorWatchdog = struct {
```

### `MonitorStopReason` (const)

Reason why monitored command execution completed.

```zig
pub const MonitorStopReason = enum {
```

### `MonitoredTerm` (const)

Result for monitored inherited command execution.

```zig
pub const MonitoredTerm = struct {
```

### `runInheritMonitored` (fn)

Runs an inherited command with watchdog timeout/liveness controls.

This routine is intended for terminal monitors (`logcat`, simulator console)
that should stop automatically when the app exits or a timeout is reached.

```zig
pub fn runInheritMonitored(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    spec: MonitorCommandSpec,
    watchdog: MonitorWatchdog,
) !MonitoredTerm {
```
