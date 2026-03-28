# `cli/src/commands/codegen/ios_host_patch/project_patcher.zig`

_Language: Zig_

PBX project text mutation helpers for the iOS host patch flow.

## Public API

### `section_markers` (const)

Well-known PBX section markers used when inserting Wizig shell phases.

```zig
pub const section_markers = struct {
```

### `begin_shell` (const)

No declaration docs available.

```zig
    pub const begin_shell = "/* Begin PBXShellScriptBuildPhase section */";
```

### `end_shell` (const)

No declaration docs available.

```zig
    pub const end_shell = "/* End PBXShellScriptBuildPhase section */";
```

### `begin_sources` (const)

No declaration docs available.

```zig
    pub const begin_sources = "/* Begin PBXSourcesBuildPhase section */";
```

### `patchProjectFile` (fn)

Patches one `.pbxproj` file on disk when its contents need updating.

```zig
pub fn patchProjectFile(
    arena: std.mem.Allocator,
    io: std.Io,
    pbx_path: []const u8,
) !bool {
```

### `patchProjectText` (fn)

Applies all Wizig pbxproj rewrites to the provided project text.

```zig
pub fn patchProjectText(
    arena: std.mem.Allocator,
    text: []const u8,
) ![]const u8 {
```
