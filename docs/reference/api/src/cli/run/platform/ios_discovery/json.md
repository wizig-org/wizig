# `src/cli/run/platform/ios_discovery/json.zig`

_Language: Zig_

Shared JSON object access helpers for iOS discovery parsing.

## Public API

### `objectString` (fn)

Returns a string value from a JSON object, or null when the field is absent or not a string.

```zig
pub fn objectString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
```

### `objectBool` (fn)

Returns a bool value from a JSON object, or null when the field is absent or not a bool.

```zig
pub fn objectBool(object: std.json.ObjectMap, key: []const u8) ?bool {
```
