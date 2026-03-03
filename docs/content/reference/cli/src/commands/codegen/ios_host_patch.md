# `cli/src/commands/codegen/ios_host_patch.zig`

_Language: Zig_

iOS host project patching for direct Xcode FFI builds.

## Problem
Direct Xcode builds do not run `wizig run`, so host projects can miss
per-app FFI packaging updates unless codegen patches build wiring.

## Approach
This module patches generated host `.xcodeproj/project.pbxproj` files with a
deterministic `PBXShellScriptBuildPhase` that builds and embeds a framework
artifact and mirrors it into a generated `.xcframework`.

## Safety
Patching is idempotent: if the phase already exists, no changes are written.

## Public API

### `PatchSummary` (const)

Summary of iOS host project patching work performed in one codegen pass.

```zig
pub const PatchSummary = struct {
```

### `ensureIosHostBuildPhase` (fn)

Ensures all discovered iOS host projects include Wizig's FFI build phase.

```zig
pub fn ensureIosHostBuildPhase(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !PatchSummary {
```
