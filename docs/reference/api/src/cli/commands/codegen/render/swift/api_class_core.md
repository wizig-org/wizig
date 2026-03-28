# `src/cli/commands/codegen/render/swift/api_class_core.zig`

_Language: Zig_

Swift API class prelude renderer (init, validation, helper calls).

All C symbols are resolved at link time via `import WizigFFI` -- no
dlopen/dlsym indirection.

Performance notes:
- `withUTF8Pointer` uses `String.withUTF8` (Swift 5.0+) for zero-copy
pointer access, avoiding `Array(value.utf8)` heap allocation.
- `callStringOutput` uses `String(decoding:as:)` to skip an
intermediate `Data` allocation.
- `callBinaryOutput` reads raw bytes from FFI and decodes via
the generated `fromBinary` static method on each struct.

## Public API

### `appendApiClassCore` (fn)

Appends the `WizigGeneratedApi` class body to `out`.

Includes: initializer, ABI/contract/wire-format validation, error reader,
status assertion, UTF-8 pointer helper, and typed call wrappers
(`callStringOutput`, `callIntOutput`, `callBoolOutput`,
`callBinaryOutput`, etc.).

```zig
pub fn appendApiClassCore(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
```
