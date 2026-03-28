# `src/cli/commands/doctor/options.zig`

_Language: Zig_

`wizig doctor` command-line parsing.

## Public API

### `DoctorOptions` (const)

Parsed `wizig doctor` CLI flags.

```zig
pub const DoctorOptions = struct {
```

### `parseDoctorOptions` (fn)

Parses doctor command flags or returns `null` for `--help`.

```zig
pub fn parseDoctorOptions(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?DoctorOptions {
```

### `printUsage` (fn)

Writes doctor usage derived from the clap metadata.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```
