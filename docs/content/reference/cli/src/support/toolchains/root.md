# `cli/src/support/toolchains/root.zig`

_Language: Zig_

Toolchain governance support package.

This package exposes manifest loading, probing, version comparison, and
lockfile generation helpers used by CLI commands.

## Public API

### `lockfile` (const)

No declaration docs available.

```zig
pub const lockfile = @import("lockfile.zig");
```

### `manifest` (const)

No declaration docs available.

```zig
pub const manifest = @import("manifest.zig");
```

### `probe` (const)

No declaration docs available.

```zig
pub const probe = @import("probe.zig");
```

### `types` (const)

No declaration docs available.

```zig
pub const types = @import("types.zig");
```

### `version` (const)

No declaration docs available.

```zig
pub const version = @import("version.zig");
```
