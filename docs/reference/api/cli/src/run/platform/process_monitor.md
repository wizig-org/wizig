# `cli/src/run/platform/process_monitor.zig`

_Language: Zig_

Watchdog-controlled inherited monitor execution.

This facade keeps the public monitor surface stable while the internals are
split across smaller helper modules.

## Public API

### `MonitorCommandSpec` (const)

No declaration docs available.

```zig
pub const MonitorCommandSpec = spec.MonitorCommandSpec;
```

### `LivenessProbe` (const)

No declaration docs available.

```zig
pub const LivenessProbe = spec.LivenessProbe;
```

### `MonitorWatchdog` (const)

No declaration docs available.

```zig
pub const MonitorWatchdog = spec.MonitorWatchdog;
```

### `MonitorStopReason` (const)

No declaration docs available.

```zig
pub const MonitorStopReason = spec.MonitorStopReason;
```

### `MonitoredTerm` (const)

No declaration docs available.

```zig
pub const MonitoredTerm = spec.MonitoredTerm;
```

### `runInheritMonitored` (fn)

Runs an inherited command with watchdog timeout/liveness controls.

```zig
pub fn runInheritMonitored(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *std.Io.Writer,
    stdout: *std.Io.Writer,
    spec_arg: MonitorCommandSpec,
    watchdog: MonitorWatchdog,
) !MonitoredTerm {
```
