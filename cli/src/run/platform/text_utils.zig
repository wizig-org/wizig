//! Text parsing helpers for CLI output and config fragments.
//!
//! The run pipeline shells out to platform tools whose output must be parsed.
//! These routines isolate common token extraction and matching behavior so
//! platform modules stay concise and testable.
const std = @import("std");

/// Returns true when any needle appears in the given haystack.
pub fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
    }
    return false;
}

/// Returns true when a byte slice array contains the target value.
pub fn containsString(items: []const []const u8, value: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, value)) return true;
    }
    return false;
}

/// Extracts a quoted `'value'` found after a marker in the input line.
pub fn extractAfterMarker(line: []const u8, marker: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, marker) orelse return null;
    const rest = line[start + marker.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '\'') orelse return null;
    return rest[0..end];
}

/// Extracts a field value following an inline prefix in structured text.
pub fn extractInlineField(line: []const u8, field_prefix: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, field_prefix) orelse return null;
    var rest = line[start + field_prefix.len ..];
    rest = std.mem.trim(u8, rest, " \t");
    if (rest.len == 0) return null;

    const comma = std.mem.indexOfScalar(u8, rest, ',');
    const brace = std.mem.indexOfScalar(u8, rest, '}');
    const end_idx = switch (comma != null and brace != null) {
        true => @min(comma.?, brace.?),
        false => comma orelse brace orelse rest.len,
    };
    return std.mem.trim(u8, rest[0..end_idx], " \t\r");
}

/// Parses the first integer token found in whitespace-delimited input.
pub fn parseFirstIntToken(comptime T: type, input: []const u8) ?T {
    var it = std.mem.tokenizeAny(u8, input, " \t\r\n");
    while (it.next()) |token| {
        if (std.fmt.parseInt(T, token, 10)) |value| return value else |_| continue;
    }
    return null;
}

/// Parses the last integer token found in whitespace/colon-delimited input.
pub fn parseLastIntToken(comptime T: type, input: []const u8) ?T {
    var it = std.mem.tokenizeAny(u8, input, " \t\r\n:");
    var last: ?T = null;
    while (it.next()) |token| {
        const value = std.fmt.parseInt(T, token, 10) catch continue;
        last = value;
    }
    return last;
}

/// Parses a simulator launch PID from `simctl launch` output.
pub fn parseLaunchPid(output: []const u8) ?u32 {
    return parseLastIntToken(u32, output);
}

/// Returns true if `adb jdwp` output includes a PID line match.
pub fn hasPidLine(output: []const u8, pid: u32) bool {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        if (std.fmt.parseInt(u32, line, 10)) |parsed| {
            if (parsed == pid) return true;
        } else |_| {}
    }
    return false;
}

/// Normalizes optional single or double quoted value fragments.
pub fn trimOptionalQuotes(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }
    if (value.len >= 2 and value[0] == '\'' and value[value.len - 1] == '\'') {
        return value[1 .. value.len - 1];
    }
    return value;
}

/// Comparator for lexicographic sorting of string slices.
pub fn lessStringSlice(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
