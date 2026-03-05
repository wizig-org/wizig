# `core/src/plugins/registry_codegen/render_lockfile.zig`

_Language: Zig_

Lockfile renderer for discovered plugin manifests.

## Public API

### `renderLockfile` (fn)

Renders deterministic lockfile text for all plugin records.

```zig
pub fn renderLockfile(allocator: std.mem.Allocator, records: []const PluginRecord) ![]u8 {
```
