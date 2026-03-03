//! Codegen command-line option parsing.
//!
//! ## Responsibilities
//! - Parse `wizig codegen` CLI arguments into a normalized options struct.
//! - Validate numeric watch settings with user-facing diagnostics.
//! - Keep parsing concerns separate from generation and watch-loop execution.
//!
//! ## Design Notes
//! - This module is intentionally small and self-contained so option behavior
//!   can evolve without touching the large generator implementation.
//! - Parsing returns explicit `error.InvalidArguments` on user input issues.
const std = @import("std");
const Io = std.Io;

/// Default watch polling interval in milliseconds.
pub const default_watch_interval_ms: u64 = 500;

/// Normalized options for `wizig codegen`.
///
/// Field semantics:
/// - `project_root`: App root path to generate into.
/// - `api_override`: Explicit contract path (`--api`) when provided.
/// - `watch`: Enables continuous incremental codegen loop.
/// - `watch_interval_ms`: Polling interval used only in watch mode.
pub const CodegenOptions = struct {
    project_root: []const u8 = ".",
    api_override: ?[]const u8 = null,
    watch: bool = false,
    watch_interval_ms: u64 = default_watch_interval_ms,
    allow_toolchain_drift: bool = false,
};

/// Parses raw CLI arguments into `CodegenOptions`.
///
/// Supported forms:
/// - Positional: `[project_root]`
/// - Contract: `--api <path>` or `--api=<path>`
/// - Watch: `--watch`
/// - Interval: `--watch-interval-ms <n>` or `--watch-interval-ms=<n>`
pub fn parseCodegenOptions(args: []const []const u8, stderr: *Io.Writer) !CodegenOptions {
    var options = CodegenOptions{};

    var i: usize = 0;
    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
        options.project_root = args[i];
        i += 1;
    }

    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--api")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --api\n");
                return error.InvalidArguments;
            }
            options.api_override = args[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--api=")) {
            options.api_override = arg["--api=".len..];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--watch")) {
            options.watch = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--allow-toolchain-drift")) {
            options.allow_toolchain_drift = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--watch-interval-ms")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --watch-interval-ms\n");
                return error.InvalidArguments;
            }
            options.watch_interval_ms = try parseWatchIntervalMs(args[i + 1], stderr);
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--watch-interval-ms=")) {
            options.watch_interval_ms = try parseWatchIntervalMs(arg["--watch-interval-ms=".len..], stderr);
            i += 1;
            continue;
        }

        try stderr.print("error: unknown codegen option '{s}'\n", .{arg});
        return error.InvalidArguments;
    }

    return options;
}

/// Parses and validates watch polling interval in milliseconds.
///
/// Validation rules:
/// - Must be an unsigned integer.
/// - Must be greater than zero.
fn parseWatchIntervalMs(raw: []const u8, stderr: *Io.Writer) !u64 {
    const value = std.fmt.parseInt(u64, raw, 10) catch {
        try stderr.print("error: invalid --watch-interval-ms value '{s}' (expected positive integer)\n", .{raw});
        return error.InvalidArguments;
    };
    if (value == 0) {
        try stderr.writeAll("error: --watch-interval-ms must be greater than zero\n");
        return error.InvalidArguments;
    }
    return value;
}

test "parseCodegenOptions defaults" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseCodegenOptions(&.{}, &err_writer.writer);
    try std.testing.expectEqualStrings(".", options.project_root);
    try std.testing.expect(options.api_override == null);
    try std.testing.expect(!options.watch);
    try std.testing.expectEqual(default_watch_interval_ms, options.watch_interval_ms);
    try std.testing.expect(!options.allow_toolchain_drift);
}

test "parseCodegenOptions parses watch and interval forms" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseCodegenOptions(
        &.{ "/tmp/App", "--watch", "--watch-interval-ms=250", "--api", "/tmp/App/wizig.api.zig", "--allow-toolchain-drift" },
        &err_writer.writer,
    );
    try std.testing.expectEqualStrings("/tmp/App", options.project_root);
    try std.testing.expect(options.watch);
    try std.testing.expectEqual(@as(u64, 250), options.watch_interval_ms);
    try std.testing.expectEqualStrings("/tmp/App/wizig.api.zig", options.api_override.?);
    try std.testing.expect(options.allow_toolchain_drift);
}

test "parseCodegenOptions rejects zero watch interval" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(
        error.InvalidArguments,
        parseCodegenOptions(&.{ "--watch-interval-ms", "0" }, &err_writer.writer),
    );
}
