//! Top-level Wizig CLI argument parsing.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

const clap_support = @import("support/clap_support.zig");

/// Supported top-level Wizig commands.
pub const Command = enum {
    build,
    create,
    run,
    plugin,
    codegen,
    doctor,
    version,
    @"self-update",
    uninstall,
};

/// Result of parsing the top-level CLI arguments.
pub const ParsedArgs = struct {
    command: ?Command,
    remaining: []const []const u8,
    help: bool,
    version: bool,
};

const parsers = .{
    .COMMAND = clap.parsers.enumeration(Command),
};

const params = clap.parseParamsComptime(
    \\-h, --help     Display this help and exit.
    \\-v, --version  Output version information and exit.
    \\<COMMAND>      Top-level command to execute.
    \\
);

/// Parses the executable arguments after the binary name.
pub fn parse(
    arena: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !ParsedArgs {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var result = clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .allocator = arena,
        .diagnostic = &diag,
        .terminating_positional = 0,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.InvalidArguments;
    };
    defer result.deinit();

    return .{
        .command = result.positionals[0],
        .remaining = iter.remaining(),
        .help = result.args.help != 0,
        .version = result.args.version != 0,
    };
}

/// Writes top-level CLI help derived from the clap specification.
pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Wizig CLI\n\n" ++
            "Usage:\n" ++
            "  wizig [options] <command>\n\n" ++
            "Commands:\n" ++
            "  build        Build app artifacts.\n" ++
            "  create       Scaffold a new Wizig project.\n" ++
            "  run          Run a generated app host.\n" ++
            "  plugin       Manage Wizig plugins.\n" ++
            "  codegen      Generate bindings and host glue.\n" ++
            "  doctor       Check SDK and toolchain health.\n" ++
            "  version      Print the installed version.\n" ++
            "  self-update  Update wizig to the latest release.\n" ++
            "  uninstall    Remove the wizig installation.\n\n" ++
            "Options:\n" ++
            "  -h, --help       Display this help and exit.\n" ++
            "  -v, --version    Output version information and exit.\n\n" ++
            "Run `wizig <command> --help` for command-specific usage.\n",
    );
}

test "parse reads help, version, command, and remaining args" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const parsed = try parse(
        std.testing.allocator,
        &err_writer.writer,
        &.{ "--version", "create", "DemoApp" },
    );
    try std.testing.expectEqual(@as(?Command, .create), parsed.command);
    try std.testing.expect(parsed.version);
    try std.testing.expect(!parsed.help);
    try std.testing.expectEqualStrings("DemoApp", parsed.remaining[0]);
}

test "parse accepts empty top-level invocation" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const parsed = try parse(std.testing.allocator, &err_writer.writer, &.{});
    try std.testing.expect(parsed.command == null);
    try std.testing.expect(!parsed.help);
    try std.testing.expect(!parsed.version);
    try std.testing.expectEqual(@as(usize, 0), parsed.remaining.len);
}
