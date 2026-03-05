# `core/src/plugins/registry_codegen/render_common.zig`

_Language: Zig_

Shared text rendering helpers used by registrant generators.

## Public API

### `appendFmt` (fn)

Appends formatted text by allocating a temporary format buffer.

```zig
pub fn appendFmt(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
```

### `appendQuoted` (fn)

Appends a JSON-style quoted string with escaping.

```zig
pub fn appendQuoted(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
```

### `appendBracketedStringArray` (fn)

Renders a bracketed quoted-string array literal.

```zig
pub fn appendBracketedStringArray(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    values: []const []u8,
) !void {
```
