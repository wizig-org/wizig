# `cli/src/commands/create/scaffold_strings.zig`

_Language: Zig_

String and identifier normalization utilities for scaffolding.

The functions in this file convert user-provided project names into stable
forms suitable for file paths, package identifiers, and generated type names.

## Public API

### `sanitizeProjectName` (fn)

Produces a filesystem-safe project name.

Allowed characters are ASCII alphanumerics plus `-` and `_`.
Spaces are normalized to `-`; all other characters are dropped.

```zig
pub fn sanitizeProjectName(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
```

### `toIdentifierLower` (fn)

Converts a project name into a lowercase identifier token.

This output is used for app identifiers and token substitutions where
punctuation must be removed and the result cannot start with a digit.

```zig
pub fn toIdentifierLower(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
```

### `sanitizePackageSegment` (fn)

Converts a project name into a Java/Kotlin package segment.

Segment output is lowercase and uses single underscores as separators.
Leading digits are guarded by prefixing `app_`.

```zig
pub fn sanitizePackageSegment(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
```

### `packageNameToPath` (fn)

Converts a dot-delimited package name to an OS-native path.

```zig
pub fn packageNameToPath(allocator: std.mem.Allocator, package_name: []const u8) ![]u8 {
```

### `toForwardSlashes` (fn)

Normalizes any path separators to forward slashes.

Template placeholder path segments use `/` regardless of host OS.

```zig
pub fn toForwardSlashes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
```

### `escapeLocalPropertiesValue` (fn)

Escapes values written into Gradle `local.properties` files.

Backslashes must be doubled to survive Java properties parsing.

```zig
pub fn escapeLocalPropertiesValue(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
```

### `toSwiftTypeName` (fn)

Converts arbitrary project names to Swift type identifiers.

Word boundaries are inferred from non-alphanumeric separators and words are
title-cased. If the first emitted character would be a digit, `A` is added.

```zig
pub fn toSwiftTypeName(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
```
