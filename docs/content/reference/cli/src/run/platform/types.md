# `cli/src/run/platform/types.zig`

_Language: Zig_

Run platform domain model types.

This module defines the structured data that is shared across the
platform-specific run pipeline. Keeping these types isolated avoids circular
imports between Android/iOS flow modules and process utilities.

## Public API

### `RunError` (const)

Public run command error set used by platform execution code.

```zig
pub const RunError = error{RunFailed};
```

### `Platform` (const)

Target platform selector parsed from CLI arguments.

```zig
pub const Platform = enum {
```

### `DebuggerMode` (const)

Debugger and monitor mode selected for the run command.

```zig
pub const DebuggerMode = enum {
```

### `RunOptions` (const)

Parsed and normalized options for platform run execution.

```zig
pub const RunOptions = struct {
```

### `IosDevice` (const)

iOS simulator selection model returned by discovery.

```zig
pub const IosDevice = struct {
```

### `AndroidDevice` (const)

Android target model returned by `adb devices -l` parsing.

```zig
pub const AndroidDevice = struct {
```

### `AndroidTarget` (const)

Android run target union supporting a connected device or an AVD profile.

```zig
pub const AndroidTarget = union(enum) {
```

### `FfiBuildInputs` (const)

Inputs used to build per-platform Wizig FFI artifacts.

```zig
pub const FfiBuildInputs = struct {
```

### `AndroidFfiArtifact` (const)

Android FFI output metadata returned after staging artifacts.

```zig
pub const AndroidFfiArtifact = struct {
```
