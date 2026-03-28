//! Parses `wizig plugin` arguments and routes them to subcommand handlers.
const std = @import("std");
const Io = std.Io;

const add_cmd = @import("add.zig");
const sync_cmd = @import("sync.zig");
const validate_cmd = @import("validate.zig");

/// Parsed plugin subcommands.
pub const Command = union(enum) {
    validate: struct {
        manifest_path: []const u8,
    },
    sync: struct {
        project_root: []const u8,
    },
    add: struct {
        source: []const u8,
        project_root: []const u8,
    },
};

/// Parses the plugin command arguments and executes the requested handler.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const command = try parse(args, stderr);
    switch (command) {
        .validate => |payload| return validate_cmd.run(arena, io, stderr, stdout, payload.manifest_path),
        .sync => |payload| return sync_cmd.run(arena, io, stderr, stdout, payload.project_root),
        .add => |payload| return add_cmd.run(arena, io, stderr, stdout, payload.source, payload.project_root),
    }
}

/// Returns a typed plugin command or reports argument validation failures.
pub fn parse(args: []const []const u8, stderr: *Io.Writer) !Command {
    if (args.len == 0) {
        try stderr.writeAll("error: plugin expects validate|sync|add\n");
        return error.InvalidArguments;
    }

    if (std.mem.eql(u8, args[0], "validate")) {
        if (args.len != 2) {
            try stderr.writeAll("error: plugin validate expects <wizig-plugin.json>\n");
            return error.InvalidArguments;
        }
        return .{ .validate = .{ .manifest_path = args[1] } };
    }

    if (std.mem.eql(u8, args[0], "sync")) {
        const project_root = if (args.len >= 2) args[1] else ".";
        if (args.len > 2) {
            try stderr.writeAll("error: plugin sync accepts at most [project_root]\n");
            return error.InvalidArguments;
        }
        return .{ .sync = .{ .project_root = project_root } };
    }

    if (std.mem.eql(u8, args[0], "add")) {
        if (args.len < 2 or args.len > 3) {
            try stderr.writeAll("error: plugin add expects <git_or_path> [project_root]\n");
            return error.InvalidArguments;
        }
        const project_root = if (args.len == 3) args[2] else ".";
        return .{ .add = .{ .source = args[1], .project_root = project_root } };
    }

    try stderr.print("error: unknown plugin command '{s}'\n", .{args[0]});
    return error.InvalidArguments;
}

test "parse accepts validate, sync, and add defaults" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const validate_result = try parse(&.{ "validate", "wizig-plugin.json" }, &err_writer.writer);
    switch (validate_result) {
        .validate => |payload| try std.testing.expectEqualStrings("wizig-plugin.json", payload.manifest_path),
        else => try std.testing.expect(false),
    }

    const sync_result = try parse(&.{"sync"}, &err_writer.writer);
    switch (sync_result) {
        .sync => |payload| try std.testing.expectEqualStrings(".", payload.project_root),
        else => try std.testing.expect(false),
    }

    const add_result = try parse(&.{ "add", "https://example.com/repo.git" }, &err_writer.writer);
    switch (add_result) {
        .add => |payload| {
            try std.testing.expectEqualStrings("https://example.com/repo.git", payload.source);
            try std.testing.expectEqualStrings(".", payload.project_root);
        },
        else => try std.testing.expect(false),
    }
}

test "parse rejects invalid plugin arguments" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(error.InvalidArguments, parse(&.{}, &err_writer.writer));
    try std.testing.expectError(error.InvalidArguments, parse(&.{"validate"}, &err_writer.writer));
    try std.testing.expectError(error.InvalidArguments, parse(&.{ "sync", ".", "extra" }, &err_writer.writer));
    try std.testing.expectError(error.InvalidArguments, parse(&.{"add"}, &err_writer.writer));
    try std.testing.expectError(error.InvalidArguments, parse(&.{"unknown"}, &err_writer.writer));
}
