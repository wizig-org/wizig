# `cli/src/support/toolchains/manifest.zig`

_Language: Zig_

Toolchains manifest loader.

This parser reads the specific policy subset Wizig uses from
`toolchains.toml` and produces strongly typed doctor policy settings.

## Public API

### `loadFromRoot` (fn)

Loads and parses `toolchains.toml` from the given SDK/workspace root.

The function also computes and stores a SHA-256 digest of the exact file
bytes so downstream lockfiles can record the precise policy snapshot used.

```zig
pub fn loadFromRoot(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    root: []const u8,
) !types.ToolchainsManifest {
```
