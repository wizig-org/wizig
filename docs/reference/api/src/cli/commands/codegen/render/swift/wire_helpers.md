# `src/cli/commands/codegen/render/swift/wire_helpers.zig`

_Language: Zig_

Emits `WizigWireReader` and `WizigWireWriter` private structs for binary
wire format v1 encoding/decoding of user-defined struct types.

Wire format v1 layout:
string:  [u32 length LE][bytes...]
int:     [i64 value LE] (8 bytes)
bool:    [u8 value] (0 or 1)
enum:    [i64 rawValue LE]
struct:  [field1][field2]... (fields in contract order)

## Public API

### `appendWireHelpers` (fn)

Appends the `WizigWireReader` and `WizigWireWriter` Swift struct
definitions to the output buffer.

```zig
pub fn appendWireHelpers(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
```
