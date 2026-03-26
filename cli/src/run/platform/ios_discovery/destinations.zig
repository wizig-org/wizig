//! iOS simulator destination parsing from `xcodebuild -showdestinations`.
const std = @import("std");
const Io = std.Io;

const process = @import("../process_supervisor.zig");
const text_utils = @import("../text_utils.zig");

/// Returns iOS simulator IDs supported by the given Xcode scheme.
pub fn discoverIosSupportedDestinationIds(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    xcode_project: []const u8,
    scheme: []const u8,
) ![]const []const u8 {
    const result = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcodebuild", "-project", xcode_project, "-scheme", scheme, "-showdestinations" },
        .cwd_path = project_dir,
        .label = "discover supported iOS destinations",
    }, .{});

    return parseSupportedDestinationIds(arena, result.stdout);
}

/// Parses supported simulator destination identifiers from `xcodebuild` output.
pub fn parseSupportedDestinationIds(
    arena: std.mem.Allocator,
    output: []const u8,
) ![]const []const u8 {
    var ids = std.ArrayList([]const u8).empty;
    errdefer ids.deinit(arena);

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (std.mem.indexOf(u8, line, "platform:iOS Simulator") == null) continue;
        const id = text_utils.extractInlineField(line, "id:") orelse continue;
        if (std.mem.startsWith(u8, id, "dvtdevice-")) continue;
        try ids.append(arena, try arena.dupe(u8, id));
    }

    return ids.toOwnedSlice(arena);
}

test "parseSupportedDestinationIds keeps only iOS simulator destinations" {
    const input =
        \\  { platform:iOS Simulator, id:00000000-0000-0000-0000-000000000001, name:iPhone 15 }
        \\  { platform:iOS Simulator, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }
        \\  { platform:macOS, id:00000000-0000-0000-0000-000000000099, name:My Mac }
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ids = try parseSupportedDestinationIds(arena.allocator(), input);
    try std.testing.expectEqual(@as(usize, 1), ids.len);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000001", ids[0]);
}
