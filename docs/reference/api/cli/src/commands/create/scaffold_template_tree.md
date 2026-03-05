# `cli/src/commands/create/scaffold_template_tree.zig`

_Language: Zig_

Template tree rendering for host scaffolds.

The helpers in this file walk template directories, apply content/path token
replacements, and materialize output trees while honoring overwrite policy.

## Public API

### `PathToken` (const)

Token replacement rule for path segments.

Keys and values are matched as raw byte slices and applied in-order.

```zig
pub const PathToken = struct {
```

### `copyTemplateTreeRendered` (fn)

Copies a template tree and renders file/path placeholders.

- Directory entries are created recursively.
- Text files are rendered using template content tokens.
- Binary files are copied byte-for-byte.
- Existing files are skipped unless `force_overwrite` is true.

```zig
pub fn copyTemplateTreeRendered(
    arena: std.mem.Allocator,
    io: std.Io,
    src_root: []const u8,
    dst_root: []const u8,
    tokens: []const fs_util.RenderToken,
    path_tokens: []const PathToken,
    force_overwrite: bool,
) !void {
```
