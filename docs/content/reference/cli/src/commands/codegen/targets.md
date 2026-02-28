# `cli/src/commands/codegen/targets.zig`

Code generation target definitions.

## Public API

### `CodegenTarget` (const)

Enumerates known host/language codegen outputs.

```zig
pub const CodegenTarget = enum {
```

### `supportedNow` (fn)

Reports whether a target is implemented in the current release.

```zig
pub fn supportedNow(target: CodegenTarget) bool {
```
