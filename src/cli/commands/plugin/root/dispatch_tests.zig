//! Tests for plugin clap dispatch helpers.
const std = @import("std");

const dispatch = @import("dispatch.zig");

test "parseSyncProjectRoot defaults to the current directory" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const project_root = (try @field(dispatch, "parseSyncProjectRoot")(
        std.testing.allocator,
        &err_writer.writer,
        &.{},
    )).?;
    try std.testing.expectEqualStrings(".", project_root);
}

test "parseAddArgs reads source and optional project root" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const parsed = (try @field(dispatch, "parseAddArgs")(
        std.testing.allocator,
        &err_writer.writer,
        &.{ "https://example.com/repo.git", "apps/demo" },
    )).?;
    try std.testing.expectEqualStrings("https://example.com/repo.git", parsed.source);
    try std.testing.expectEqualStrings("apps/demo", parsed.project_root);
}
