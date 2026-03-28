//! `wizig version` output and help.
const std = @import("std");
const Io = std.Io;
const build_options = @import("build_options");

/// Writes the installed Wizig version string.
pub fn printVersion(writer: *Io.Writer) !void {
    try writer.writeAll(build_options.version);
    try writer.writeAll("\n");
}

/// Writes usage help for `wizig version`.
pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Version:\n" ++
            "  wizig version    Print the installed version\n\n" ++
            "Options:\n" ++
            "  -h, --help      Display this help and exit.\n",
    );
}

test "printUsage includes version syntax" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    const output = out_writer.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig version") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--help") != null);
}
