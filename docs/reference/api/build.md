# `build.zig`

_Language: Zig_

Wizig build graph.

This file defines build/install targets for:
- CLI executable (`wizig`)
- Core and compatibility modules
- FFI static/shared libraries
- Installed SDK/runtime/templates assets

## Public API

### `build` (fn)

Configures all build steps for Wizig.

```zig
pub fn build(b: *std.Build) void {
```
