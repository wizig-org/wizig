//! Unified run option parsing and root resolution.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

const clap_support = @import("../../support/clap_support.zig");
const types = @import("types.zig");

const parsers = .{
    .PROJECT_ROOT = clap.parsers.string,
    .DEVICE = clap.parsers.string,
    .DEBUGGER = clap.parsers.string,
    .SECONDS = clap.parsers.string,
};

const params = clap.parseParamsComptime(
    \\-h, --help                     Display this help and exit.
    \\    --device <DEVICE>          Select target without prompting.
    \\    --debugger <DEBUGGER>      Override delegated debugger mode.
    \\    --non-interactive          Fail instead of prompting for selection.
    \\    --once                     Launch and exit without the monitor loop.
    \\    --monitor-timeout <SECONDS>  Stop the monitor after N seconds.
    \\    --regenerate-host          Regenerate iOS hosts before running.
    \\    --allow-toolchain-drift    Skip project toolchain lock enforcement.
    \\<PROJECT_ROOT>                 Generated app root containing ios/ or android/.
    \\
);

/// Parses unified run options or returns `null` for `--help`.
pub fn parseUnifiedOptions(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?types.UnifiedOptions {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var result = clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.RunFailed;
    };
    defer result.deinit();

    if (result.args.help != 0) return null;
    return .{
        .project_root = result.positionals[0] orelse ".",
        .device_selector = result.args.device,
        .debugger_mode = result.args.debugger,
        .non_interactive = @field(result.args, "non-interactive") != 0,
        .once = result.args.once != 0,
        .monitor_timeout_seconds = if (@field(result.args, "monitor-timeout")) |raw|
            try parseMonitorTimeout(raw, stderr)
        else
            null,
        .regenerate_host = @field(result.args, "regenerate-host") != 0,
        .allow_toolchain_drift = @field(result.args, "allow-toolchain-drift") != 0,
    };
}

/// Writes unified run help with the optional project directory default.
pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Run:\n" ++
            "  wizig run [project_dir] [options]\n\n" ++
            "Options:\n" ++
            "  -h, --help                         Display this help and exit.\n" ++
            "      --device <DEVICE>              Select target without prompting.\n" ++
            "      --debugger <DEBUGGER>          Override delegated debugger mode.\n" ++
            "      --non-interactive              Fail instead of prompting for selection.\n" ++
            "      --once                         Launch and exit without the monitor loop.\n" ++
            "      --monitor-timeout <SECONDS>    Stop the monitor after N seconds.\n" ++
            "      --regenerate-host              Regenerate iOS hosts before running.\n" ++
            "      --allow-toolchain-drift        Skip project toolchain lock enforcement.\n\n" ++
            "Arguments:\n" ++
            "  [project_dir]                      Generated app root. Defaults to current directory.\n",
    );
}

/// Parses monitor timeout seconds from CLI input.
fn parseMonitorTimeout(raw: []const u8, stderr: *Io.Writer) !u64 {
    const seconds = std.fmt.parseInt(u64, raw, 10) catch {
        try stderr.print("error: invalid --monitor-timeout value '{s}' (expected positive integer seconds)\n", .{raw});
        return error.RunFailed;
    };
    if (seconds == 0) {
        try stderr.writeAll("error: --monitor-timeout must be greater than zero seconds\n");
        return error.RunFailed;
    }
    return seconds;
}

/// Resolves a project root to an absolute path.
pub fn resolveProjectRoot(arena: std.mem.Allocator, io: std.Io, root: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(root)) {
        return arena.dupe(u8, root);
    }
    const cwd = try std.process.currentPathAlloc(io, arena);
    return std.fs.path.resolve(arena, &.{ cwd, root });
}

test "parseUnifiedOptions defaults" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = (try parseUnifiedOptions(std.testing.allocator, &err_writer.writer, &.{})).?;
    try std.testing.expectEqualStrings(".", options.project_root);
    try std.testing.expect(options.device_selector == null);
    try std.testing.expect(options.debugger_mode == null);
    try std.testing.expect(options.monitor_timeout_seconds == null);
    try std.testing.expect(!options.non_interactive);
    try std.testing.expect(!options.once);
    try std.testing.expect(!options.regenerate_host);
    try std.testing.expect(!options.allow_toolchain_drift);
}

test "parseUnifiedOptions parses project and flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = (try parseUnifiedOptions(
        std.testing.allocator,
        &err_writer.writer,
        &.{ "examples/app/WizigExample", "--device", "emulator-5554", "--debugger", "none", "--monitor-timeout", "75", "--once", "--regenerate-host", "--allow-toolchain-drift" },
    )).?;
    try std.testing.expectEqualStrings("examples/app/WizigExample", options.project_root);
    try std.testing.expectEqualStrings("emulator-5554", options.device_selector.?);
    try std.testing.expectEqualStrings("none", options.debugger_mode.?);
    try std.testing.expectEqual(@as(?u64, 75), options.monitor_timeout_seconds);
    try std.testing.expect(options.once);
    try std.testing.expect(options.regenerate_host);
    try std.testing.expect(options.allow_toolchain_drift);
}

test "parseUnifiedOptions rejects zero monitor timeout" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(
        error.RunFailed,
        parseUnifiedOptions(std.testing.allocator, &err_writer.writer, &.{ "--monitor-timeout", "0" }),
    );
}

test "printUsage documents optional project dir" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    try std.testing.expect(std.mem.indexOf(u8, out_writer.writer.buffered(), "[project_dir]") != null);
}
