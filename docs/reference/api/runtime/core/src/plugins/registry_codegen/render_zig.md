# `runtime/core/src/plugins/registry_codegen/render_zig.zig`

_Language: Zig_

Zig registrant renderer for discovered plugins.

## Public API

### `renderZigRegistrant` (fn)

Renders Zig registrant source from discovered plugins.

```zig
pub fn renderZigRegistrant(allocator: std.mem.Allocator, records: []const PluginRecord) ![]u8 {
```
