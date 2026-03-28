//! Shared zig-clap helpers for slice-based CLI parsing.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

/// Lightweight iterator adapter for `[]const []const u8` argument slices.
pub const SliceIterator = struct {
    args: []const []const u8,
    index: usize = 0,

    /// Creates an iterator over a borrowed argument slice.
    pub fn init(args: []const []const u8) SliceIterator {
        return .{ .args = args };
    }

    /// Returns the next argument or `null` when exhausted.
    pub fn next(self: *SliceIterator) ?[]const u8 {
        if (self.index >= self.args.len) return null;
        defer self.index += 1;
        return self.args[self.index];
    }

    /// Returns the unconsumed suffix after partial parsing.
    pub fn remaining(self: *const SliceIterator) []const []const u8 {
        return self.args[self.index..];
    }
};

/// Prints a clap diagnostic to stderr and flushes immediately.
pub fn reportDiagnostic(stderr: *Io.Writer, diag: clap.Diagnostic, err: anyerror) !void {
    try stderr.writeAll("error: ");
    try diag.report(stderr, err);
    try stderr.flush();
}

/// Writes a one-line usage string prefixed with the command invocation.
pub fn writeUsageLine(
    writer: *Io.Writer,
    prefix: []const u8,
    comptime params: []const clap.Param(clap.Help),
) !void {
    try writer.writeAll(prefix);
    try clap.usage(writer, clap.Help, params);
    try writer.writeAll("\n");
}

/// Writes an options block generated from the clap parameter specification.
pub fn writeOptionsBlock(
    writer: *Io.Writer,
    comptime params: []const clap.Param(clap.Help),
) !void {
    try clap.help(writer, clap.Help, params, .{
        .indent = 2,
        .description_indent = 2,
        .description_on_new_line = false,
    });
    try writer.writeAll("\n");
}
