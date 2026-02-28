# `cli/src/main.zig`

Wizig CLI entrypoint and command router.

## Public API

### `main` (fn)

Parses top-level CLI arguments and dispatches to command handlers.

```zig
pub fn main(init: std.process.Init) !void {
```
