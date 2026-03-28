# `src/cli/commands/codegen/render/swift_api.zig`

_Language: Zig_

Renderer for `WizigGeneratedApi.swift`.

Produces a self-contained Swift source file that uses binary wire encoding
(wire format v1) for struct marshalling across the FFI boundary. No
Foundation dependency is required.

## Public API

### `renderSwiftApi` (fn)

Renders the complete `WizigGeneratedApi.swift` source file.

```zig
pub fn renderSwiftApi(
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
    compat: compatibility.Metadata,
) ![]u8 {
```
