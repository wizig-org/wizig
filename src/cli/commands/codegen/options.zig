//! Codegen command-line option parsing.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

const clap_support = @import("../../support/clap_support.zig");

/// Default watch polling interval in milliseconds.
pub const default_watch_interval_ms: u64 = 500;

/// Normalized options for `wizig codegen`.
pub const CodegenOptions = struct {
    project_root: []const u8 = ".",
    api_override: ?[]const u8 = null,
    watch: bool = false,
    watch_interval_ms: u64 = default_watch_interval_ms,
    allow_toolchain_drift: bool = false,
};

const parsers = .{
    .PATH = clap.parsers.string,
    .MILLISECONDS = clap.parsers.int(u64, 10),
    .PROJECT_ROOT = clap.parsers.string,
};

const params = clap.parseParamsComptime(
    \\-h, --help                            Display this help and exit.
    \\    --api <PATH>                     Override the default API contract path.
    \\    --watch                          Enable incremental watch mode.
    \\    --watch-interval-ms <MILLISECONDS>  Polling interval for watch mode.
    \\    --allow-toolchain-drift          Skip toolchain lock enforcement.
    \\<PROJECT_ROOT>                       Project root to generate into.
    \\
);

/// Parses raw CLI arguments into `CodegenOptions`.
pub fn parseCodegenOptions(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?CodegenOptions {
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
    const watch_interval_ms = result.args.@"watch-interval-ms" orelse default_watch_interval_ms;
    if (watch_interval_ms == 0) {
        try stderr.writeAll("error: --watch-interval-ms must be greater than zero\n");
        try stderr.flush();
        return error.InvalidArguments;
    }

    return .{
        .project_root = result.positionals[0] orelse ".",
        .api_override = result.args.api,
        .watch = result.args.watch != 0,
        .watch_interval_ms = watch_interval_ms,
        .allow_toolchain_drift = result.args.@"allow-toolchain-drift" != 0,
    };
}

/// Writes `wizig codegen` usage with the optional project root default.
pub fn printUsage(writer: *Io.Writer) !void {
    try writer.print(
        "Codegen:\n" ++
            "  wizig codegen [project_root] [options]\n\n" ++
            "Options:\n" ++
            "  -h, --help                                Display this help and exit.\n" ++
            "      --api <PATH>                          Override the default API contract path.\n" ++
            "      --watch                               Enable incremental watch mode.\n" ++
            "      --watch-interval-ms <MILLISECONDS>    Polling interval for watch mode.\n" ++
            "      --allow-toolchain-drift               Skip toolchain lock enforcement.\n\n" ++
            "Arguments:\n" ++
            "  [project_root]                            Project root to generate into. Defaults to current directory.\n\n" ++
            "Notes:\n" ++
            "  Default contract lookup: wizig.api.zig -> wizig.api.json (optional)\n" ++
            "  Watch mode: incremental codegen on lib/**/*.zig and contract changes\n" ++
            "  Current targets: zig, swift, kotlin\n" ++
            "  Default watch interval: {d}ms\n",
        .{default_watch_interval_ms},
    );
}

test "parseCodegenOptions defaults" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = (try parseCodegenOptions(std.testing.allocator, &err_writer.writer, &.{})).?;
    try std.testing.expectEqualStrings(".", options.project_root);
    try std.testing.expect(options.api_override == null);
    try std.testing.expect(!options.watch);
    try std.testing.expectEqual(default_watch_interval_ms, options.watch_interval_ms);
    try std.testing.expect(!options.allow_toolchain_drift);
}

test "parseCodegenOptions parses watch and interval forms" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = (try parseCodegenOptions(
        std.testing.allocator,
        &err_writer.writer,
        &.{ "/tmp/App", "--watch", "--watch-interval-ms=250", "--api", "/tmp/App/wizig.api.zig", "--allow-toolchain-drift" },
    )).?;
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
        parseCodegenOptions(std.testing.allocator, &err_writer.writer, &.{ "--watch-interval-ms", "0" }),
    );
}

test "printUsage documents optional project root" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    try std.testing.expect(std.mem.indexOf(u8, out_writer.writer.buffered(), "[project_root]") != null);
}
