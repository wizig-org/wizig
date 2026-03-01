# `cli/src/commands/doctor/root.zig`

_Language: Zig_

`wizig doctor` diagnostics for host tools and bundled assets.

This command validates host tool presence/version against policy from
`toolchains.toml` and supports strict enforcement mode.

## Public API

### `run` (fn)

Runs environment diagnostics and toolchain policy checks.

The command validates SDK bundle presence, then checks host tools against
`toolchains.toml` policy and reports warning/failure based on strict mode.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
```

### `printUsage` (fn)

Writes usage help for the doctor command.

Keep this in sync with `parseDoctorOptions` whenever flags are added.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
