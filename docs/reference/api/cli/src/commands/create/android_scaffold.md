# `cli/src/commands/create/android_scaffold.zig`

_Language: Zig_

Android host scaffold generation.

This module renders the Android template tree, normalizes package-related
identifiers, and writes local SDK hints used by Gradle.

## Public API

### `createAndroid` (fn)

Creates the Android host scaffold and initializes local build metadata.

When Android SDK paths are available in the environment this function writes
`local.properties` to make `./gradlew` usable immediately.

```zig
pub fn createAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    templates_root: []const u8,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    force_host_overwrite: bool,
) !void {
```
