# `cli/src/run/platform/text_utils.zig`

_Language: Zig_

Text parsing helpers for CLI output and config fragments.

The run pipeline shells out to platform tools whose output must be parsed.
These routines isolate common token extraction and matching behavior so
platform modules stay concise and testable.

## Public API

### `containsAny` (fn)

Returns true when any needle appears in the given haystack.

```zig
pub fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
```

### `containsString` (fn)

Returns true when a byte slice array contains the target value.

```zig
pub fn containsString(items: []const []const u8, value: []const u8) bool {
```

### `extractAfterMarker` (fn)

Extracts a quoted `'value'` found after a marker in the input line.

```zig
pub fn extractAfterMarker(line: []const u8, marker: []const u8) ?[]const u8 {
```

### `extractInlineField` (fn)

Extracts a field value following an inline prefix in structured text.

```zig
pub fn extractInlineField(line: []const u8, field_prefix: []const u8) ?[]const u8 {
```

### `parseFirstIntToken` (fn)

Parses the first integer token found in whitespace-delimited input.

```zig
pub fn parseFirstIntToken(comptime T: type, input: []const u8) ?T {
```

### `parseLastIntToken` (fn)

Parses the last integer token found in whitespace/colon-delimited input.

```zig
pub fn parseLastIntToken(comptime T: type, input: []const u8) ?T {
```

### `parseLaunchPid` (fn)

Parses a simulator launch PID from `simctl launch` output.

```zig
pub fn parseLaunchPid(output: []const u8) ?u32 {
```

### `hasPidLine` (fn)

Returns true if `adb jdwp` output includes a PID line match.

```zig
pub fn hasPidLine(output: []const u8, pid: u32) bool {
```

### `trimOptionalQuotes` (fn)

Normalizes optional single or double quoted value fragments.

```zig
pub fn trimOptionalQuotes(value: []const u8) []const u8 {
```

### `lessStringSlice` (fn)

Comparator for lexicographic sorting of string slices.

```zig
pub fn lessStringSlice(_: void, a: []const u8, b: []const u8) bool {
```
