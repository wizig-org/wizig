# `src/cli/commands/codegen/ios_host_patch/settings_patch.zig`

_Language: Zig_

Build-configuration rewrites for iOS host pbxproj patching.

## Public API

### `disableUserScriptSandboxingForAppTarget` (fn)

Disables user script sandboxing only for the application target configs.

Invariant: project-level and test target configurations remain untouched.

```zig
pub fn disableUserScriptSandboxingForAppTarget(
    arena: std.mem.Allocator,
    text: []const u8,
) ![]const u8 {
```

### `enableAutomaticSigningForAppTarget` (fn)

Enables Xcode automatic signing for the application target configs.

```zig
pub fn enableAutomaticSigningForAppTarget(
    arena: std.mem.Allocator,
    text: []const u8,
) ![]const u8 {
```
