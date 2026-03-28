# `src/cli/commands/codegen/render/zig_ffi_wire_codegen.zig`

_Language: Zig_

Binary wire format code generation helpers for struct marshalling.

Emits wire-format read (decode) and write (encode) code for
user-defined structs, reading/writing fields in contract order
using the binary wire format v1.

## Public API

### `findStruct` (fn)

Finds a struct definition by name in the known struct list.

```zig
pub fn findStruct(structs: []const api.UserStruct, name: []const u8) ?api.UserStruct {
```

### `appendWireReadStruct` (fn)

Emits binary wire decode for a struct, reading fields in contract order.

```zig
pub fn appendWireReadStruct(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    struct_name: []const u8,
    result_var: []const u8,
    structs: []const api.UserStruct,
) std.mem.Allocator.Error!void {
```

### `appendStructBinaryEncode` (fn)

Emits binary wire encoding for a struct output value.

```zig
pub fn appendStructBinaryEncode(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    struct_name: []const u8,
    structs: []const api.UserStruct,
) !void {
```
