# `templates/app/wizig.api.zig`

_Language: Zig_

Optional Zig API contract overrides for Wizig codegen.

Discovery from `lib/**/*.zig` works without this file.
Edit this file only when you need explicit method/event declarations.
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
