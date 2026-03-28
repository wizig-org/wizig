# `src/cli/run/platform/process_monitor/liveness.zig`

_Language: Zig_

Liveness-probe execution for monitored inherited processes.

## Public API

### `probeAppLiveness` (fn)

Runs the liveness probe and evaluates whether the app is still alive.

```zig
pub fn probeAppLiveness(io: std.Io, probe: spec.LivenessProbe) bool {
```

### `livenessProbeSatisfied` (fn)

No declaration docs available.

```zig
pub fn livenessProbeSatisfied(probe: spec.LivenessProbe, result: std.process.RunResult) bool {
```
