# `runtime/core/src/root.zig`

Runtime-packaged core API surface shipped into generated apps.

## Public API

### `Runtime` (const)

Runtime instance used by host bridges.

```zig
pub const Runtime = @import("runtime.zig").Runtime;
```

### `PluginManifest` (const)

Plugin manifest schema representation.

```zig
pub const PluginManifest = @import("plugins/manifest.zig").PluginManifest;
```

### `PluginRegistry` (const)

In-memory plugin registry.

```zig
pub const PluginRegistry = @import("plugins/registry_codegen.zig").Registry;
```

### `PluginRecord` (const)

Single plugin record entry.

```zig
pub const PluginRecord = @import("plugins/registry_codegen.zig").PluginRecord;
```

### `collectPluginRegistry` (const)

Collects plugin manifests from a directory tree.

```zig
pub const collectPluginRegistry = @import("plugins/registry_codegen.zig").collectFromDir;
```

### `renderPluginLockfile` (const)

Renders deterministic plugin lockfile text.

```zig
pub const renderPluginLockfile = @import("plugins/registry_codegen.zig").renderLockfile;
```

### `renderZigRegistrant` (const)

Renders Zig plugin registrant source.

```zig
pub const renderZigRegistrant = @import("plugins/registry_codegen.zig").renderZigRegistrant;
```

### `renderSwiftRegistrant` (const)

Renders Swift plugin registrant source.

```zig
pub const renderSwiftRegistrant = @import("plugins/registry_codegen.zig").renderSwiftRegistrant;
```

### `renderKotlinRegistrant` (const)

Renders Kotlin plugin registrant source.

```zig
pub const renderKotlinRegistrant = @import("plugins/registry_codegen.zig").renderKotlinRegistrant;
```
