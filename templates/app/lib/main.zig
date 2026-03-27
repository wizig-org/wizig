//! Template Zig module scaffolded into new Wizig apps.
const std = @import("std");

/// Returns the application name configured at scaffold time.
pub fn appName() []const u8 {
    return "{{APP_NAME}}";
}

/// Echo helper used by host examples and smoke tests.
pub fn echo(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{s}", .{ appName(), input });
}

pub fn echoZig(input: []const u8) void {
    std.debug.print("⚡ Hello {s} from Zig - App: {s}", .{ input, appName() });
}

test "appName is non-empty" {
    try std.testing.expect(appName().len > 0);
}
