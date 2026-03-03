# `cli/src/commands/codegen/root.zig`

_Language: Zig_

`wizig codegen` command orchestration and public wrappers.

## Public API

### `ApiContractSource` (const)

No declaration docs available.

```zig
pub const ApiContractSource = contract_source.ApiContractSource;
```

### `ResolvedApiContract` (const)

No declaration docs available.

```zig
pub const ResolvedApiContract = contract_source.ResolvedApiContract;
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

Generates Zig/Swift/Kotlin API bindings from contract + `lib/**/*.zig` discovery.

```zig
pub fn generateProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) !void {
```
