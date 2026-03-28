# `cli/src/run/platform/ios_ffi/framework.zig`

_Language: Zig_

Low-level iOS FFI framework helpers.

The build and bundle modules share these helpers for Mach-O page alignment,
byte-for-byte equality checks, and framework Info.plist generation.

## Public API

### `fixMachoTextPageAlignment` (fn)

Fixes Mach-O `__TEXT` segment page alignment for iOS arm64 AMFI validation.

```zig
pub fn fixMachoTextPageAlignment(io: std.Io, path: []const u8) !void {
```

### `resignAdHoc` (fn)

Re-signs a Mach-O binary with an ad-hoc identity after in-place fixups.

```zig
pub fn resignAdHoc(
    arena: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) void {
```

### `filesEqual` (fn)

Returns `true` when both files exist and contain identical bytes.

```zig
pub fn filesEqual(
    arena: std.mem.Allocator,
    io: std.Io,
    src_path: []const u8,
    dst_path: []const u8,
) !bool {
```

### `writeFrameworkInfoPlist` (fn)

Writes the framework `Info.plist` used by iOS bundle validators.

```zig
pub fn writeFrameworkInfoPlist(io: std.Io, out_path: []const u8) !void {
```
