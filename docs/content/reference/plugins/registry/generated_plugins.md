# `plugins/registry/generated_plugins.zig`

Generated static plugin registry used by tooling/runtime integration.

## Public API

### `RegisteredPlugin` (const)

Single plugin descriptor entry.

```zig
pub const RegisteredPlugin = struct {
```

### `plugins` (const)

Statically-registered plugins discovered during sync.

```zig
pub const plugins: []const RegisteredPlugin = &.{
```
