# `cli/src/run/platform/config_parse.zig`

_Language: Zig_

Lightweight parsers for Android manifest/Gradle and iOS build settings.

These helpers intentionally avoid heavy dependencies and focus on extracting
the specific fields needed by the run pipeline.

## Public API

### `extractBuildSetting` (fn)

Extracts a key from `xcodebuild -showBuildSettings` output.

```zig
pub fn extractBuildSetting(settings: []const u8, key: []const u8) ?[]const u8 {
```

### `extractXmlAttribute` (fn)

Extracts an XML attribute from the first matching element tag.

```zig
pub fn extractXmlAttribute(xml: []const u8, tag_name: []const u8, attr_name: []const u8) ?[]const u8 {
```

### `extractGradleStringValue` (fn)

Extracts a Kotlin-DSL style `key = "value"` declaration.

```zig
pub fn extractGradleStringValue(content: []const u8, key: []const u8) ?[]const u8 {
```

### `inferSchemeFromProject` (fn)

Derives Xcode scheme name from `.xcodeproj` folder name.

```zig
pub fn inferSchemeFromProject(project_path: []const u8) ?[]const u8 {
```

### `normalizeAndroidComponent` (fn)

Converts `com.app.Activity` or `.Activity` into `app/.Activity` component.

```zig
pub fn normalizeAndroidComponent(
    arena: std.mem.Allocator,
    app_id: []const u8,
    activity: []const u8,
) ![]const u8 {
```
