//! Path helpers shared across CLI commands.
const std = @import("std");

/// Joins two path segments with the platform separator.
pub fn join(allocator: std.mem.Allocator, base: []const u8, name: []const u8) ![]u8 {
    if (std.mem.eql(u8, base, ".")) {
        return allocator.dupe(u8, name);
    }
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ base, std.fs.path.sep_str, name });
}

/// Resolves a possibly-relative path into an absolute path.
pub fn resolveAbsolute(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return arena.dupe(u8, path);
    const cwd = try std.process.currentPathAlloc(io, arena);
    return std.fs.path.resolve(arena, &.{ cwd, path });
}

/// Returns parent directory path or "." when no parent exists.
pub fn parentDirAlloc(arena: std.mem.Allocator, path: []const u8) ![]u8 {
    const maybe = std.fs.path.dirname(path);
    if (maybe) |value| return arena.dupe(u8, value);
    return arena.dupe(u8, ".");
}

/// Normalizes path separators to `/`.
pub fn normalizeSlashes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, input);
    for (out) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
    return out;
}

/// Trims optional matching quote characters around a value.
pub fn trimOptionalQuotes(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }
    if (value.len >= 2 and value[0] == '\'' and value[value.len - 1] == '\'') {
        return value[1 .. value.len - 1];
    }
    return value;
}
