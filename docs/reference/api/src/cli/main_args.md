# `src/cli/main_args.zig`

_Language: Zig_

Top-level Wizig CLI argument parsing.

## Public API

### `Command` (const)

Supported top-level Wizig commands.

```zig
pub const Command = enum {
```

### `ParsedArgs` (const)

Result of parsing the top-level CLI arguments.

```zig
pub const ParsedArgs = struct {
```

### `parse` (fn)

Parses the executable arguments after the binary name.

```zig
pub fn parse(
    arena: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !ParsedArgs {
```

### `printUsage` (fn)

Writes top-level CLI help derived from the clap specification.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```
