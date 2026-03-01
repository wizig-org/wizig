# `cli/src/run/platform/root.zig`

_Language: Zig_

Platform-specific run pipeline used by unified run selection.

This module replaces the former monolithic `cli/src/run/legacy.zig` file with a
modular package under `cli/src/run/platform/`.

## Public API

### `run` (fn)

Executes platform run pipeline (`ios` or `android`) with parsed options.

### `printUsage` (fn)

Writes platform run usage help.
