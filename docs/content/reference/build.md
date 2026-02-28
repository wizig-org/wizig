# `build.zig`

Ziggy build graph.

This file defines build/install targets for:
- CLI executable (`ziggy`)
- Core and compatibility modules
- FFI static/shared libraries
- Installed SDK/runtime/templates assets

## Public API

### `build` (fn)

Configures all build steps for Ziggy.

```zig
pub fn build(b: *std.Build) void {
```
