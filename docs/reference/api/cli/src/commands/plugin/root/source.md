# `cli/src/commands/plugin/root/source.zig`

_Language: Zig_

Source classification helpers for `wizig plugin add`.

## Public API

### `isLikelyGitSource` (fn)

Returns true for source strings that look like git remotes.

```zig
pub fn isLikelyGitSource(source: []const u8) bool {
```

### `repoNameFromSource` (fn)

Derives a destination directory name from a git source or filesystem path.

```zig
pub fn repoNameFromSource(source: []const u8) []const u8 {
```
