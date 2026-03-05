# `cli/src/commands/codegen/watch/fingerprint.zig`

_Language: Zig_

Incremental fingerprinting for codegen watch mode.

## Purpose
Watch mode needs a cheap signal for "inputs changed". This module computes a
deterministic SHA-256 fingerprint using file metadata (path, size, mtime)
rather than re-reading every file on every poll.

## Tracked Inputs
- `lib/**/*.zig` (excluding `lib/WizigGeneratedAppModule.zig`)
- contract selection and contract metadata (`wizig.api.zig` / `.json` / `--api`)
- presence of required generated outputs (to recover from deleted artifacts)

## Performance Characteristics
- O(number of Zig source files) stat calls per poll.
- No large file reads, minimizing overhead during active editing.

## Public API

### `computeWatchFingerprint` (fn)

Computes the current watch fingerprint for a codegen project.

Parameters:
- `project_root`: Absolute project root path.
- `api_path`: Resolved contract path when available, otherwise `null`.

```zig
pub fn computeWatchFingerprint(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    api_path: ?[]const u8,
) ![32]u8 {
```
