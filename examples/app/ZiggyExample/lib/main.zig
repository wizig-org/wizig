const std = @import("std");

pub fn appName() []const u8 {
    return "ZiggyExample";
}

test "appName is non-empty" {
    try std.testing.expect(appName().len > 0);
}
