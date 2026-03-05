# `cli/src/commands/codegen/render/ios_c_headers.zig`

_Language: Zig_

iOS C header and modulemap renderers for framework imports.

These artifacts are generated to keep direct C-ABI access available in Xcode
while still supporting the higher-level Swift wrapper surface.

## Public API

### `renderGeneratedApiHeader` (fn)

Renders C declarations for all generated `wizig_api_*` exports plus runtime
and FFI infrastructure symbols needed by `import WizigFFI`.

```zig
pub fn renderGeneratedApiHeader(arena: std.mem.Allocator, spec: api.ApiSpec) ![]u8 {
```

### `renderFrameworkUmbrellaHeader` (fn)

Renders the framework umbrella header that imports runtime + generated APIs.

```zig
pub fn renderFrameworkUmbrellaHeader(arena: std.mem.Allocator) ![]u8 {
```

### `renderFrameworkModuleMap` (fn)

Renders modulemap for framework-based imports in Swift/ObjC tooling.

```zig
pub fn renderFrameworkModuleMap(arena: std.mem.Allocator) ![]u8 {
```
