# `src/cli/run/platform/process_monitor/runner.zig`

_Language: Zig_

Monitored inherited-process execution with timeout and liveness controls.

## Public API

### `runInheritMonitored` (fn)

Runs an inherited command with watchdog timeout/liveness controls.

```zig
pub fn runInheritMonitored(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    monitor_spec: spec.MonitorCommandSpec,
    watchdog: spec.MonitorWatchdog,
) !spec.MonitoredTerm {
```

### `effectivePollIntervalSeconds` (fn)

No declaration docs available.

```zig
pub fn effectivePollIntervalSeconds(seconds: u64) u64 {
```
