const std = @import("std");

pub fn appName() []const u8 {
    return "{{APP_NAME}}";
}

pub fn echo(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{s}", .{ appName(), input });
}

test "appName is non-empty" {
    try std.testing.expect(appName().len > 0);
}
