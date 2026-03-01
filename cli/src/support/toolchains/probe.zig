//! Host tool version probing.
//!
//! These helpers execute tool-specific version commands and normalize the
//! resulting version tokens for policy validation and lock-file capture.
const std = @import("std");

const process_util = @import("../process.zig");
const types = @import("types.zig");

/// Probes all tool versions using the provided policy ordering.
///
/// The caller controls ordering via `policies`; this function preserves index
/// alignment so each probe can be compared against the matching policy entry.
pub fn probeAll(
    arena: std.mem.Allocator,
    io: std.Io,
    policies: []const types.ToolPolicy,
) [types.tool_count]types.ToolProbe {
    var out: [types.tool_count]types.ToolProbe = undefined;
    for (policies, 0..) |policy, idx| {
        out[idx] = probeOne(arena, io, policy.id);
    }
    return out;
}

/// Probes one tool and returns presence/version metadata.
///
/// Probe failures are reported as `present = false` so callers can distinguish
/// between missing binaries and version-policy mismatches.
pub fn probeOne(arena: std.mem.Allocator, io: std.Io, tool: types.ToolId) types.ToolProbe {
    const argv = commandForTool(tool);
    const result = process_util.runCapture(arena, io, null, argv, null) catch {
        return .{ .id = tool, .present = false, .version = null };
    };

    const success = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!success) {
        return .{ .id = tool, .present = false, .version = null };
    }

    const parsed = parseVersion(tool, result.stdout, result.stderr);
    return .{ .id = tool, .present = true, .version = if (parsed.len == 0) null else parsed };
}

/// Maps each tool id to a command that emits version information.
fn commandForTool(tool: types.ToolId) []const []const u8 {
    return switch (tool) {
        .zig => &.{ "zig", "version" },
        .xcodebuild => &.{ "xcodebuild", "-version" },
        .xcodegen => &.{ "xcodegen", "version" },
        .java => &.{ "java", "-version" },
        .gradle => &.{ "gradle", "--version" },
        .adb => &.{ "adb", "version" },
    };
}

/// Extracts a normalized version string from tool output streams.
///
/// Individual tools require custom heuristics because formats vary widely
/// between command implementations and operating systems.
fn parseVersion(tool: types.ToolId, stdout: []const u8, stderr: []const u8) []const u8 {
    return switch (tool) {
        .zig => extractFirstVersionLikeToken(stdout) orelse "",
        .xcodebuild => extractXcodeVersion(stdout) orelse "",
        .xcodegen => extractFirstVersionLikeToken(stdout) orelse extractFirstVersionLikeToken(stderr) orelse "",
        .java => extractQuotedVersion(stderr) orelse extractQuotedVersion(stdout) orelse extractFirstVersionLikeToken(stderr) orelse "",
        .gradle => extractGradleVersion(stdout) orelse "",
        .adb => extractAdbVersion(stdout) orelse extractFirstVersionLikeToken(stdout) orelse "",
    };
}

/// Parses `xcodebuild -version` output.
fn extractXcodeVersion(text: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (std.mem.startsWith(u8, line, "Xcode ")) {
            return std.mem.trim(u8, line["Xcode ".len..], " \t\r");
        }
    }
    return null;
}

/// Parses `gradle --version` output.
fn extractGradleVersion(text: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (std.mem.startsWith(u8, line, "Gradle ")) {
            return std.mem.trim(u8, line["Gradle ".len..], " \t\r");
        }
    }
    return null;
}

/// Parses `adb version` output.
fn extractAdbVersion(text: []const u8) ?[]const u8 {
    const marker = "Android Debug Bridge version";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (!std.mem.startsWith(u8, line, marker)) continue;
        const rest = std.mem.trim(u8, line[marker.len..], " \t\r");
        return extractFirstVersionLikeToken(rest);
    }
    return null;
}

/// Extracts the first quoted token, used by Java version output parsing.
fn extractQuotedVersion(text: []const u8) ?[]const u8 {
    const first_quote = std.mem.indexOfScalar(u8, text, '"') orelse return null;
    const rest = text[first_quote + 1 ..];
    const second_quote = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..second_quote];
}

/// Finds the first token that resembles a version identifier.
///
/// A valid candidate must contain digits and either a separator (`.` or `-`)
/// or start with a digit.
fn extractFirstVersionLikeToken(text: []const u8) ?[]const u8 {
    var tokens = std.mem.tokenizeAny(u8, text, " \t\r\n:=()[]{}");
    while (tokens.next()) |token| {
        var has_digit = false;
        for (token) |ch| {
            if (std.ascii.isDigit(ch)) {
                has_digit = true;
                break;
            }
        }
        if (!has_digit) continue;

        var has_separator = false;
        for (token) |ch| {
            if (ch == '.' or ch == '-') {
                has_separator = true;
                break;
            }
        }
        if (has_separator or std.ascii.isDigit(token[0])) return token;
    }
    return null;
}

test "extractors parse typical tool outputs" {
    try std.testing.expectEqualStrings("26.1", extractXcodeVersion("Xcode 26.1\nBuild version 17A100\n").?);
    try std.testing.expectEqualStrings("9.2.1", extractGradleVersion("\nGradle 9.2.1\n").?);
    try std.testing.expectEqualStrings("1.0.41", extractAdbVersion("Android Debug Bridge version 1.0.41\nVersion 36.0.0\n").?);
    try std.testing.expectEqualStrings("21.0.3", extractQuotedVersion("openjdk version \"21.0.3\" 2025-04-15\n").?);
}
