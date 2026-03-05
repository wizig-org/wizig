# `runtime/core/src/plugins/registry_codegen/render_swift.zig`

_Language: Zig_

Swift registrant renderer for discovered plugins.

## Public API

### `renderSwiftRegistrant` (fn)

Renders Swift registrant source from discovered plugins.

```zig
pub fn renderSwiftRegistrant(allocator: std.mem.Allocator, records: []const PluginRecord) ![]u8 {
```
