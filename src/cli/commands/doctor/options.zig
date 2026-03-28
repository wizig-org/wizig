//! `wizig doctor` command-line parsing.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

const clap_support = @import("../../support/clap_support.zig");

/// Parsed `wizig doctor` CLI flags.
pub const DoctorOptions = struct {
    explicit_sdk_root: ?[]const u8 = null,
    strict: ?bool = null,
};

const parsers = .{
    .PATH = clap.parsers.string,
};

const params = clap.parseParamsComptime(
    \\-h, --help         Display this help and exit.
    \\    --sdk-root <PATH>  Explicit Wizig SDK bundle root.
    \\    --strict       Force strict toolchain enforcement.
    \\    --no-strict    Disable strict toolchain enforcement.
    \\
);

/// Parses doctor command flags or returns `null` for `--help`.
pub fn parseDoctorOptions(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?DoctorOptions {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var result = clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.InvalidArguments;
    };
    defer result.deinit();

    if (result.args.help != 0) return null;

    return .{
        .explicit_sdk_root = result.args.@"sdk-root",
        .strict = resolveStrict(args),
    };
}

/// Writes doctor usage derived from the clap metadata.
pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll("Doctor:\n  ");
    try clap_support.writeUsageLine(writer, "wizig doctor ", &params);
    try writer.writeAll("\nOptions:\n");
    try clap_support.writeOptionsBlock(writer, &params);
}

test "parseDoctorOptions parses strict and sdk-root" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const parsed = (try parseDoctorOptions(
        std.testing.allocator,
        &err_writer.writer,
        &.{ "--strict", "--sdk-root", "/tmp/wizig" },
    )).?;
    try std.testing.expectEqual(@as(?bool, true), parsed.strict);
    try std.testing.expectEqualStrings("/tmp/wizig", parsed.explicit_sdk_root.?);
}

fn resolveStrict(args: []const []const u8) ?bool {
    var strict: ?bool = null;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--strict")) strict = true;
        if (std.mem.eql(u8, arg, "--no-strict")) strict = false;
    }
    return strict;
}

test "parseDoctorOptions keeps the last strict flag" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const parsed = (try parseDoctorOptions(
        std.testing.allocator,
        &err_writer.writer,
        &.{ "--strict", "--no-strict" },
    )).?;
    try std.testing.expectEqual(@as(?bool, false), parsed.strict);
}
