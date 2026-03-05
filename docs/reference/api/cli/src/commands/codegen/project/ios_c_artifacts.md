# `cli/src/commands/codegen/project/ios_c_artifacts.zig`

_Language: Zig_

iOS C interop artifact generation for framework packaging.

This module writes generated headers/modulemap under `.wizig/generated/ios`
so the Xcode build phase can package an App Store-safe XCFramework that is
discoverable by Swift/ObjC IDE tooling.

## Public API

### `GeneratedPaths` (const)

File paths for generated iOS framework interop artifacts.

```zig
pub const GeneratedPaths = struct {
```

### `GenerateResult` (const)

Result of generating iOS framework interop artifacts.

```zig
pub const GenerateResult = struct {
```

### `generate` (fn)

Writes iOS C headers and modulemap for the current project API surface.

```zig
pub fn generate(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *std.Io.Writer,
    project_root: []const u8,
    generated_root: []const u8,
    spec: api.ApiSpec,
) !GenerateResult {
```
