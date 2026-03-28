# `src/cli/commands/plugin/root/help.zig`

_Language: Zig_

Help text renderers for `wizig plugin`.

## Public API

### `printUsage` (fn)

Writes summary help for `wizig plugin`.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```

### `printValidateUsage` (fn)

Writes `wizig plugin validate` usage.

```zig
pub fn printValidateUsage(writer: *Io.Writer) !void {
```

### `printSyncUsage` (fn)

Writes `wizig plugin sync` usage.

```zig
pub fn printSyncUsage(writer: *Io.Writer) !void {
```

### `printAddUsage` (fn)

Writes `wizig plugin add` usage.

```zig
pub fn printAddUsage(writer: *Io.Writer) !void {
```
