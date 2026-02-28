# `cli/src/commands/codegen/root.zig`

`ziggy codegen` command and typed API binding generators.

## Public API

### `ApiContractSource` (const)

Supported contract source formats.

```zig
pub const ApiContractSource = enum {
```

### `ResolvedApiContract` (const)

Resolved API contract file path and format.

```zig
pub const ResolvedApiContract = struct {
```

### `run` (fn)

Parses codegen CLI options and triggers project generation.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
```

### `printUsage` (fn)

Writes usage help for the codegen command.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```

### `resolveApiContract` (fn)

Resolves API contract path from explicit override or project defaults.

```zig
pub fn resolveApiContract(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) !?ResolvedApiContract {
```

### `generateProject` (fn)

Generates Zig/Swift/Kotlin API bindings from `ziggy.api.zig` or `ziggy.api.json`.

```zig
pub fn generateProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: []const u8,
) !void {
```
