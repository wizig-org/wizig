# `runtime/core/src/plugins/registry_codegen/render_kotlin.zig`

_Language: Zig_

Kotlin registrant renderer for discovered plugins.

## Public API

### `renderKotlinRegistrant` (fn)

Renders Kotlin registrant source from discovered plugins.

```zig
pub fn renderKotlinRegistrant(allocator: std.mem.Allocator, records: []const PluginRecord) ![]u8 {
```
