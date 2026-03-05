# `cli/src/support/toolchains/version.zig`

_Language: Zig_

Version parsing and comparison helpers.

The toolchain policy compares minimum versions across heterogeneous command
outputs (`xcodebuild`, `java`, `adb`, etc.). These helpers normalize version
strings into numeric components and perform conservative `>=` checks.

## Public API

### `isAtLeast` (fn)

Returns true when `actual` is greater than or equal to `minimum`.

```zig
pub fn isAtLeast(actual: []const u8, minimum: []const u8) bool {
```

### `parseNumericParts` (fn)

Extracts up to three numeric version components from free-form text.

```zig
pub fn parseNumericParts(input: []const u8) NumericParts {
```

### `NumericParts` (const)

Compact representation of parsed numeric version components.

```zig
pub const NumericParts = struct {
```
