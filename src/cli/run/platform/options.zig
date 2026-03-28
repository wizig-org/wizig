//! Public facade for platform run option parsing.
const std = @import("std");

const parse = @import("options_parse.zig");
const types = @import("types.zig");

/// Parses CLI arguments into validated platform run options.
pub fn parseRunOptions(
    allocator: std.mem.Allocator,
    stderr: *std.Io.Writer,
    args: []const []const u8,
) !?types.RunOptions {
    return parse.parseRunOptions(allocator, stderr, args);
}

test {
    _ = @import("options_parse.zig");
}
