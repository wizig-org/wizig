# `src/cli/commands/version.zig`

_Language: Zig_

`wizig version` output and help.

## Public API

### `printVersion` (fn)

Writes the installed Wizig version string.

```zig
pub fn printVersion(writer: *Io.Writer) !void {
```

### `printUsage` (fn)

Writes usage help for `wizig version`.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```
