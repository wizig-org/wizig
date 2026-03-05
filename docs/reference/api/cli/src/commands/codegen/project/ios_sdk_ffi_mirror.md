# `cli/src/commands/codegen/project/ios_sdk_ffi_mirror.zig`

_Language: Zig_

Mirrors generated iOS FFI artifacts into the local SwiftPM SDK package.

## Public API

### `mirrorGeneratedIosFfiArtifacts` (fn)

Mirrors generated C headers + C shim source into `.wizig/sdk/ios/Sources/WizigFFI`.

```zig
pub fn mirrorGeneratedIosFfiArtifacts(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    spec: api.ApiSpec,
) !void {
```
