# `cli/src/support/toolchains/types.zig`

_Language: Zig_

Shared toolchain policy types.

These definitions are consumed by manifest parsing, version probing, doctor
diagnostics, and lock-file generation.

## Public API

### `ToolId` (const)

Stable set of host tools checked by Wizig doctor and captured in lockfiles.

The ordering of this enum is intentionally treated as policy order across:
- doctor output rendering,
- lockfile serialization, and
- manifest parsing defaults.

```zig
pub const ToolId = enum {
```

### `tool_count` (const)

Number of supported tool ids.

```zig
pub const tool_count = @typeInfo(ToolId).@"enum".fields.len;
```

### `ToolPolicy` (const)

Per-tool policy loaded from `toolchains.toml`.

`min_version` is evaluated using semantic-ish numeric token comparison and
is expected to be non-empty for every known tool.

```zig
pub const ToolPolicy = struct {
```

### `DoctorPolicy` (const)

Doctor policy section loaded from `toolchains.toml`.

`strict_default` controls baseline behavior when `wizig doctor` is run
without explicit strictness flags.

```zig
pub const DoctorPolicy = struct {
```

### `ToolchainsManifest` (const)

Manifest payload used by CLI components.

`manifest_sha256_hex` is computed from raw `toolchains.toml` bytes so
lockfiles can capture the exact policy snapshot used at scaffold time.

```zig
pub const ToolchainsManifest = struct {
```

### `ToolProbe` (const)

One probed tool version result from host environment.

`present` distinguishes command availability from parse success. If present
is true but parsing fails, `version` is null.

```zig
pub const ToolProbe = struct {
```

### `toolDisplayName` (fn)

Human-readable display label for a tool.

Used for command-line diagnostics where explicit policy keys are not needed.

```zig
pub fn toolDisplayName(tool: ToolId) []const u8 {
```

### `toolJsonKey` (fn)

Serialization key for lockfile JSON tool maps.

These values are stable and must match `toolchains.toml` doctor subsection
identifiers to keep parser and serializer behavior aligned.

```zig
pub fn toolJsonKey(tool: ToolId) []const u8 {
```

### `orderedTools` (fn)

Returns all known tools in deterministic policy order.

Callers use this for default construction and index-based matching where
compact fixed-size arrays are preferred over hash maps.

```zig
pub fn orderedTools() [tool_count]ToolId {
```
