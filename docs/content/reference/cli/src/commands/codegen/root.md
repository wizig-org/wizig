# `cli/src/commands/codegen/root.zig`

_Language: Zig_

`wizig codegen` command and typed API binding generators.

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

### `EnsureCodegenOptions` (const)

Behavior options for cache-aware project generation.

```zig
pub const EnsureCodegenOptions = struct {
```

### `EnsureCodegenResult` (const)

Outcome of cache-aware generation.

```zig
pub const EnsureCodegenResult = enum {
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

### `ensureProjectGenerated` (fn)

Ensures generated bindings are up-to-date using manifest fingerprint caching.

```zig
pub fn ensureProjectGenerated(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
    options: EnsureCodegenOptions,
) !EnsureCodegenResult {
```

### `generateProject` (fn)

Generates Zig/Swift/Kotlin API bindings from optional contract + `lib/**/*.zig` discovery.

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
