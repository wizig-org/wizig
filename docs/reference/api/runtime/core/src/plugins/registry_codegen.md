# `runtime/core/src/plugins/registry_codegen.zig`

_Language: Zig_

Plugin registry collection and registrant source generation.

## Public API

### `PluginRecord` (const)

Plugin file path paired with parsed manifest contents.

```zig
pub const PluginRecord = types.PluginRecord;
```

### `Registry` (const)

In-memory registry of discovered plugins.

```zig
pub const Registry = types.Registry;
```

### `collectFromDir` (const)

Collects plugin manifests from the given `plugins_dir`.

```zig
pub const collectFromDir = collector.collectFromDir;
```

### `renderLockfile` (const)

Renders deterministic lockfile text for all plugin records.

```zig
pub const renderLockfile = render_lockfile.renderLockfile;
```

### `renderZigRegistrant` (const)

Renders Zig registrant source from discovered plugins.

```zig
pub const renderZigRegistrant = render_zig.renderZigRegistrant;
```

### `renderSwiftRegistrant` (const)

Renders Swift registrant source from discovered plugins.

```zig
pub const renderSwiftRegistrant = render_swift.renderSwiftRegistrant;
```

### `renderKotlinRegistrant` (const)

Renders Kotlin registrant source from discovered plugins.

```zig
pub const renderKotlinRegistrant = render_kotlin.renderKotlinRegistrant;
```
