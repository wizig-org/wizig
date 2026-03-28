# `src/cli/run/platform/process_monitor/spec.zig`

_Language: Zig_

Public monitor execution types and command-path helpers.

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

### `childCwd` (fn)

Converts nullable cwd string into `Child.Cwd` representation.

```zig
pub fn childCwd(path: ?[]const u8) std.process.Child.Cwd {
```
