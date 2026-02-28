const std = @import("std");
const path_util = @import("path.zig");

pub fn pathExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

pub fn ensureDir(io: std.Io, path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, path);
}

pub fn writeFileAtomically(io: std.Io, path: []const u8, contents: []const u8) !void {
    var atomic_file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .make_path = true,
        .replace = true,
    });
    defer atomic_file.deinit(io);

    try atomic_file.file.writeStreamingAll(io, contents);
    try atomic_file.replace(io);
}

pub fn removeTreeIfExists(io: std.Io, path: []const u8) !void {
    if (!pathExists(io, path)) return;
    try std.Io.Dir.cwd().deleteTree(io, path);
}

pub fn copyTree(
    arena: std.mem.Allocator,
    io: std.Io,
    src_root: []const u8,
    dst_root: []const u8,
) !void {
    var src_dir = try std.Io.Dir.cwd().openDir(io, src_root, .{ .iterate = true });
    defer src_dir.close(io);

    try std.Io.Dir.cwd().createDirPath(io, dst_root);

    var walker = try src_dir.walk(arena);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (shouldSkipEntry(entry.path)) continue;

        const src_path = try path_util.join(arena, src_root, entry.path);
        const dst_path = try path_util.join(arena, dst_root, entry.path);

        switch (entry.kind) {
            .directory => try std.Io.Dir.cwd().createDirPath(io, dst_path),
            .file => {
                const bytes = try std.Io.Dir.cwd().readFileAlloc(io, src_path, arena, .limited(256 * 1024 * 1024));
                try writeFileAtomically(io, dst_path, bytes);
            },
            else => {},
        }
    }
}

pub fn readTemplate(
    arena: std.mem.Allocator,
    io: std.Io,
    templates_root: []const u8,
    relative_path: []const u8,
) ![]u8 {
    const full = try path_util.join(arena, templates_root, relative_path);
    return std.Io.Dir.cwd().readFileAlloc(io, full, arena, .limited(1024 * 1024));
}

pub const RenderToken = struct {
    key: []const u8,
    value: []const u8,
};

pub fn renderTemplate(
    arena: std.mem.Allocator,
    template: []const u8,
    tokens: []const RenderToken,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    var i: usize = 0;
    while (i < template.len) {
        if (i + 1 < template.len and template[i] == '{' and template[i + 1] == '{') {
            const end = std.mem.indexOfPos(u8, template, i + 2, "}}") orelse {
                try out.append(arena, template[i]);
                i += 1;
                continue;
            };
            const key_raw = template[i + 2 .. end];
            const key = std.mem.trim(u8, key_raw, " \t\r\n");
            var replaced = false;
            for (tokens) |token| {
                if (std.mem.eql(u8, token.key, key)) {
                    try out.appendSlice(arena, token.value);
                    replaced = true;
                    break;
                }
            }
            if (!replaced) {
                try out.appendSlice(arena, template[i .. end + 2]);
            }
            i = end + 2;
            continue;
        }
        try out.append(arena, template[i]);
        i += 1;
    }

    return out.toOwnedSlice(arena);
}

fn shouldSkipEntry(entry_path: []const u8) bool {
    var it = std.mem.splitAny(u8, entry_path, "/\\");
    while (it.next()) |segment| {
        if (segment.len == 0) continue;
        if (std.mem.eql(u8, segment, ".build")) return true;
        if (std.mem.eql(u8, segment, ".gradle")) return true;
        if (std.mem.eql(u8, segment, "build")) return true;
        if (std.mem.eql(u8, segment, ".DS_Store")) return true;
    }
    return false;
}
