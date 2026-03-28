# `cli/src/commands/codegen/project/spec/equality.zig`

_Language: Zig_

Equality helpers for API spec merge validation.

## Public API

### `apiTypesEqual` (fn)

Returns whether two API type descriptors are structurally equal.

```zig
pub fn apiTypesEqual(lhs: api.ApiType, rhs: api.ApiType) bool {
```

### `structsEqual` (fn)

Returns whether two user struct definitions are structurally equal.

```zig
pub fn structsEqual(lhs: api.UserStruct, rhs: api.UserStruct) bool {
```

### `enumsEqual` (fn)

Returns whether two user enum definitions are structurally equal.

```zig
pub fn enumsEqual(lhs: api.UserEnum, rhs: api.UserEnum) bool {
```
