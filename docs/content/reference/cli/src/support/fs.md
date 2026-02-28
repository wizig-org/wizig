# `cli/src/support/fs.zig`

Filesystem helpers used by Wizig CLI commands.

## Public API

### `pathExists` (fn)

Returns true when `path` exists.

```zig
pub fn pathExists(io: std.Io, path: []const u8) bool {
```

### `ensureDir` (fn)

Creates a directory tree if it does not already exist.

```zig
pub fn ensureDir(io: std.Io, path: []const u8) !void {
```

### `writeFileAtomically` (fn)

Atomically writes `contents` to `path`, creating parents as needed.

```zig
pub fn writeFileAtomically(io: std.Io, path: []const u8, contents: []const u8) !void {
```

### `removeTreeIfExists` (fn)

Removes `path` tree if present; no-op when missing.

```zig
pub fn removeTreeIfExists(io: std.Io, path: []const u8) !void {
```

### `copyTree` (fn)

Recursively copies `src_root` into `dst_root`.

```zig
pub fn copyTree(
    arena: std.mem.Allocator,
    io: std.Io,
    src_root: []const u8,
    dst_root: []const u8,
) !void {
```

### `readTemplate` (fn)

Loads a template file from `<templates_root>/<template_rel>`.

```zig
pub fn readTemplate(
    arena: std.mem.Allocator,
    io: std.Io,
    templates_root: []const u8,
    relative_path: []const u8,
) ![]u8 {
```

### `RenderToken` (const)

Token replacement entry used by template rendering.

```zig
pub const RenderToken = struct {
```

### `renderTemplate` (fn)

Replaces `{{KEY}}` placeholders in template content.

```zig
pub fn renderTemplate(
    arena: std.mem.Allocator,
    template: []const u8,
    tokens: []const RenderToken,
) ![]u8 {
```
