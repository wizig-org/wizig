# `cli/src/run/unified/discovery.zig`

_Language: Zig_

Host and device discovery for unified run mode.

Unified run needs lightweight, platform-agnostic discovery to choose a
concrete target before delegating into platform-specific execution.

## Public API

### `hasIosHost` (fn)

Returns true when the project has an iOS host with at least one `.xcodeproj`.

```zig
pub fn hasIosHost(arena: std.mem.Allocator, io: std.Io, ios_dir: []const u8) bool {
```

### `hasAndroidHost` (fn)

Returns true when the project has Android host Gradle module files.

```zig
pub fn hasAndroidHost(io: std.Io, android_dir: []const u8) bool {
```

### `discoverIosDevicesNonShutdown` (fn)

Discovers booted/available iOS simulators and excludes `Shutdown` state.

```zig
pub fn discoverIosDevicesNonShutdown(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
) ![]types.DeviceInfo {
```

### `discoverAndroidDevices` (fn)

Discovers connected Android devices from adb output.

```zig
pub fn discoverAndroidDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.DeviceInfo {
```

### `chooseCandidate` (fn)

Resolves target candidate by selector or interactive prompt.

```zig
pub fn chooseCandidate(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    candidates: []const types.Candidate,
    selector: ?[]const u8,
    non_interactive: bool,
) !types.Candidate {
```
