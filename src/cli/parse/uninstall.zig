//! `wizig uninstall` clap-backed argument parsing.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

pub const UninstallOptions = struct {
    yes: bool = false,
};

const params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\-y, --yes   Skip the confirmation prompt.
    \\
);

/// Parses `wizig uninstall` flags or returns `null` for `--help`.
pub fn parseUninstallOptions(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?UninstallOptions {
    var diag = clap.Diagnostic{};
    var iter = clap.args.SliceIterator{ .args = args };
    var parsed = clap.parseEx(clap.Help, &params, clap.parsers.default, &iter, .{
        .allocator = arena,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        try stderr.flush();
        return error.InvalidArguments;
    };
    defer parsed.deinit();

    if (parsed.args.help != 0) return null;
    return .{ .yes = parsed.args.yes != 0 };
}

test "parseUninstallOptions accepts yes flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const parsed = (try parseUninstallOptions(std.testing.allocator, std.testing.io, &err_writer.writer, &.{"-y"})).?;
    try std.testing.expect(parsed.yes);
}

test "parseUninstallOptions rejects unknown flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(
        error.InvalidArguments,
        parseUninstallOptions(std.testing.allocator, std.testing.io, &err_writer.writer, &.{"--force"}),
    );
}
