# `src/cli/commands/codegen/ios_host_patch.zig`

_Language: Zig_

iOS host project patching for direct Xcode FFI builds.

Direct Xcode builds do not run `wizig run`, so codegen keeps generated host
projects wired to the current FFI packaging flow by patching the project
file deterministically and idempotently.

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
