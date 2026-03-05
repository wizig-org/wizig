# `cli/src/commands/codegen/render/swift/api_class_methods.zig`

_Language: Zig_

Swift API method and event emitter renderer.

Methods call C exports through the static `WizigFFI` import. User structs and
enums are translated to wire representations automatically:
- structs -> JSON string wire
- enums   -> Int64 raw value wire

## Public API

### `appendApiClassMethods` (fn)

Appends generated API methods plus sink event forwarding methods.

```zig
pub fn appendApiClassMethods(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
) !void {
```
