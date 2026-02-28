//! Example application Zig logic module.
const std = @import("std");

/// Returns the logical app name.
pub fn appName() []const u8 {
    return "WizigExample";
}

test "appName is non-empty" {
    try std.testing.expect(appName().len > 0);
}
