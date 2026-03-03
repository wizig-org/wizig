//! Shared text rendering helpers used by registrant generators.
const std = @import("std");

/// Appends formatted text by allocating a temporary format buffer.
pub fn appendFmt(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

/// Appends a JSON-style quoted string with escaping.
pub fn appendQuoted(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try out.append(allocator, '"');
    try appendEscaped(out, allocator, value);
    try out.append(allocator, '"');
}

/// Escapes control characters and quotes for generated source literals.
fn appendEscaped(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    for (value) |ch| {
        switch (ch) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, ch),
        }
    }
}

/// Renders a bracketed quoted-string array literal.
pub fn appendBracketedStringArray(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    values: []const []u8,
) !void {
    try out.append(allocator, '[');
    for (values, 0..) |value, i| {
        if (i != 0) try out.appendSlice(allocator, ", ");
        try appendQuoted(out, allocator, value);
    }
    try out.append(allocator, ']');
}
