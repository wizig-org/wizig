# `src/cli/run/platform/ios_discovery/destinations.zig`

_Language: Zig_

iOS simulator destination parsing from `xcodebuild -showdestinations`.

## Public API

### `discoverIosSupportedDestinationIds` (fn)

Returns iOS simulator IDs supported by the given Xcode scheme.

```zig
pub fn discoverIosSupportedDestinationIds(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    xcode_project: []const u8,
    scheme: []const u8,
) ![]const []const u8 {
```

### `parseSupportedDestinationIds` (fn)

Parses supported simulator destination identifiers from `xcodebuild` output.

```zig
pub fn parseSupportedDestinationIds(
    arena: std.mem.Allocator,
    output: []const u8,
) ![]const []const u8 {
```
