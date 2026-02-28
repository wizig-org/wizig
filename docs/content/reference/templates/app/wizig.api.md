# `templates/app/wizig.api.zig`

Zig-first API contract for Wizig codegen.

Edit this file to define the typed host <-> Zig surface.
Supported scalar tags today: `.string`, `.int`, `.bool`, `.void`.

## Public API

### `namespace` (const)

Logical namespace used by generated bindings.

```zig
pub const namespace = "{{APP_IDENTIFIER}}";
```

### `methods` (const)

Host-callable methods (host -> Zig).

```zig
pub const methods = .{
```

### `events` (const)

Zig-emitted events (Zig -> host).

```zig
pub const events = .{
```
