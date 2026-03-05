# `cli/src/run/platform/process_supervisor.zig`

_Language: Zig_

Centralized process supervision for the run pipeline.

This module is the single execution surface for child processes used by
platform runners. It standardizes spawn/capture semantics, exit handling,
and diagnostics so terminal output behavior stays consistent across iOS and
Android flows.

## Public API

### `CommandResult` (const)

Alias for captured process output.

```zig
pub const CommandResult = std.process.RunResult;
```

### `CaptureLimits` (const)

Capture size limits for stdout/stderr.

```zig
pub const CaptureLimits = struct {
```

### `CommandSpec` (const)

Parameters that describe a single child process invocation.

```zig
pub const CommandSpec = struct {
```

### `MonitorCommandSpec` (const)

Monitor command spec for inherited watchdog execution.

```zig
pub const MonitorCommandSpec = monitor.MonitorCommandSpec;
```

### `LivenessProbe` (const)

App liveness probe settings used by monitor watchdog execution.

```zig
pub const LivenessProbe = monitor.LivenessProbe;
```

### `MonitorWatchdog` (const)

Watchdog controls for long-running monitor commands.

```zig
pub const MonitorWatchdog = monitor.MonitorWatchdog;
```

### `MonitorStopReason` (const)

Reason why monitored command execution completed.

```zig
pub const MonitorStopReason = monitor.MonitorStopReason;
```

### `MonitoredTerm` (const)

Result for monitored inherited command execution.

```zig
pub const MonitoredTerm = monitor.MonitoredTerm;
```

### `runCapture` (fn)

Executes a child process with captured stdout/stderr.

This is intentionally used for short-lived commands whose output is parsed.
For long-running monitors, use `runInheritTerm` or `runInheritMonitored`.

```zig
pub fn runCapture(
    arena: Allocator,
    io: std.Io,
    spec: CommandSpec,
    limits: CaptureLimits,
) !CommandResult {
```

### `runCaptureChecked` (fn)

Executes a captured command and returns `RunFailed` on non-zero exit.

On failure, this routine prints both captured streams so users retain full
command context without hunting in intermediate logs.

```zig
pub fn runCaptureChecked(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    spec: CommandSpec,
    limits: CaptureLimits,
) !CommandResult {
```

### `runInheritTerm` (fn)

Spawns a child process with inherited stdio and waits for termination.

This is used for interactive processes or log streams where immediate
terminal visibility is more useful than buffered capture.

```zig
pub fn runInheritTerm(
    io: std.Io,
    stderr: *Io.Writer,
    spec: CommandSpec,
) !std.process.Child.Term {
```

### `runInheritMonitored` (fn)

Runs an inherited command with watchdog timeout/liveness controls.

This delegates to `process_monitor.zig` so monitor-specific logic remains
isolated from short-lived command execution behavior.

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

### `runInheritChecked` (fn)

Runs an inherited command and fails on non-zero termination.

This helper keeps error reporting consistent for build/install phases while
preserving direct terminal output streaming from child tools.

```zig
pub fn runInheritChecked(
    io: std.Io,
    stderr: *Io.Writer,
    spec: CommandSpec,
) !void {
```

### `termIsSuccess` (fn)

Returns whether a process terminated with successful exit code.

```zig
pub fn termIsSuccess(term: std.process.Child.Term) bool {
```

### `termIsInterrupted` (fn)

Returns whether a process terminated due to user interrupt signal.

```zig
pub fn termIsInterrupted(term: std.process.Child.Term) bool {
```

### `termLabel` (fn)

Returns a compact label for a child termination state.

```zig
pub fn termLabel(term: std.process.Child.Term) []const u8 {
```
