# `src/cli/commands/create/options.zig`

_Language: Zig_

`wizig create` argument parsing and validation.

## Public API

### `CreateRequest` (const)

Parsed `wizig create` request values.

```zig
pub const CreateRequest = struct {
```

### `parseCreateRequest` (fn)

Parses CLI arguments into a scaffold request or `null` for `--help`.

```zig
pub fn parseCreateRequest(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?CreateRequest {
```

### `printUsage` (fn)

Writes `wizig create` usage with optional destination semantics.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```
