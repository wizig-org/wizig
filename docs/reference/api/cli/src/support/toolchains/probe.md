# `cli/src/support/toolchains/probe.zig`

_Language: Zig_

Host tool version probing.

These helpers execute tool-specific version commands and normalize the
resulting version tokens for policy validation and lock-file capture.

## Public API

### `probeAll` (fn)

Probes all tool versions using the provided policy ordering.

The caller controls ordering via `policies`; this function preserves index
alignment so each probe can be compared against the matching policy entry.

```zig
pub fn probeAll(
    arena: std.mem.Allocator,
    io: std.Io,
    policies: []const types.ToolPolicy,
) [types.tool_count]types.ToolProbe {
```

### `probeOne` (fn)

Probes one tool and returns presence/version metadata.

Probe failures are reported as `present = false` so callers can distinguish
between missing binaries and version-policy mismatches.

```zig
pub fn probeOne(arena: std.mem.Allocator, io: std.Io, tool: types.ToolId) types.ToolProbe {
```
