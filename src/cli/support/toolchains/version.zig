//! Version parsing and comparison helpers.
//!
//! The toolchain policy compares minimum versions across heterogeneous command
//! outputs (`xcodebuild`, `java`, `adb`, etc.). These helpers normalize version
//! strings into numeric components and perform conservative `>=` checks.
const std = @import("std");

/// Returns true when `actual` is greater than or equal to `minimum`.
pub fn isAtLeast(actual: []const u8, minimum: []const u8) bool {
    const actual_parts = parseNumericParts(actual);
    const min_parts = parseNumericParts(minimum);
    if (actual_parts.count == 0 or min_parts.count == 0) return false;

    var idx: usize = 0;
    while (idx < 3) : (idx += 1) {
        const a = actual_parts.parts[idx];
        const m = min_parts.parts[idx];
        if (a > m) return true;
        if (a < m) return false;
    }
    return true;
}

/// Extracts up to three numeric version components from free-form text.
pub fn parseNumericParts(input: []const u8) NumericParts {
    var out = NumericParts{};

    var idx: usize = 0;
    while (idx < input.len and out.count < out.parts.len) {
        if (!std.ascii.isDigit(input[idx])) {
            idx += 1;
            continue;
        }

        const start = idx;
        while (idx < input.len and std.ascii.isDigit(input[idx])) : (idx += 1) {}
        const slice = input[start..idx];
        const parsed = std.fmt.parseInt(u32, slice, 10) catch 0;
        out.parts[out.count] = parsed;
        out.count += 1;
    }

    return out;
}

/// Compact representation of parsed numeric version components.
pub const NumericParts = struct {
    parts: [3]u32 = .{ 0, 0, 0 },
    count: usize = 0,
};

test "isAtLeast handles semver and suffixes" {
    try std.testing.expect(isAtLeast("0.16.0-dev.731+abc", "0.15.1"));
    try std.testing.expect(isAtLeast("26.1", "26.0.0"));
    try std.testing.expect(!isAtLeast("9.1.9", "9.2.1"));
    try std.testing.expect(isAtLeast("21", "21.0.0"));
}

test "parseNumericParts extracts first three numeric groups" {
    const parsed = parseNumericParts("Android Debug Bridge version 1.0.41");
    try std.testing.expectEqual(@as(usize, 3), parsed.count);
    try std.testing.expectEqual(@as(u32, 1), parsed.parts[0]);
    try std.testing.expectEqual(@as(u32, 0), parsed.parts[1]);
    try std.testing.expectEqual(@as(u32, 41), parsed.parts[2]);
}
