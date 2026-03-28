//! `wizig plugin` clap-backed subcommand dispatch.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

const add_cmd = @import("add.zig");
const help = @import("help.zig");
const sync_cmd = @import("sync.zig");
const validate_cmd = @import("validate.zig");
const clap_support = @import("../../../support/clap_support.zig");

const Command = enum { validate, sync, add };
const AddArgs = struct { source: []const u8, project_root: []const u8 };

const main_parsers = .{ .COMMAND = clap.parsers.enumeration(Command) };
const validate_parsers = .{ .MANIFEST = clap.parsers.string };
const sync_parsers = .{ .PROJECT_ROOT = clap.parsers.string };
const add_parsers = .{
    .SOURCE = clap.parsers.string,
    .PROJECT_ROOT = clap.parsers.string,
};

const main_params = clap.parseParamsComptime(
    \\-h, --help      Display this help and exit.
    \\<COMMAND>       Plugin subcommand to execute.
    \\
);
const validate_params = clap.parseParamsComptime(
    \\-h, --help      Display this help and exit.
    \\<MANIFEST>      Path to wizig-plugin.json.
    \\
);
const sync_params = clap.parseParamsComptime(
    \\-h, --help          Display this help and exit.
    \\<PROJECT_ROOT>      Project root to sync into.
    \\
);
const add_params = clap.parseParamsComptime(
    \\-h, --help          Display this help and exit.
    \\<SOURCE>            Git URL or local plugin path.
    \\<PROJECT_ROOT>      Project root to add into.
    \\
);

/// Parses plugin arguments and executes the selected subcommand.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var parsed = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .allocator = arena,
        .diagnostic = &diag,
        .terminating_positional = 0,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.InvalidArguments;
    };
    defer parsed.deinit();

    if (parsed.args.help != 0) {
        try help.printUsage(stdout);
        try stdout.flush();
        return;
    }

    const command = parsed.positionals[0] orelse {
        try stderr.writeAll("error: plugin expects validate|sync|add\n");
        try stderr.flush();
        return error.InvalidArguments;
    };

    switch (command) {
        .validate => try runValidate(arena, io, stderr, stdout, iter.remaining()),
        .sync => try runSync(arena, io, stderr, stdout, iter.remaining()),
        .add => try runAdd(arena, io, stderr, stdout, iter.remaining()),
    }
}

/// Writes plugin command usage text.
pub fn printUsage(writer: *Io.Writer) !void {
    return help.printUsage(writer);
}

fn runValidate(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const manifest_path = (try parseValidateArgs(arena, stderr, args)) orelse {
        try help.printValidateUsage(stdout);
        try stdout.flush();
        return;
    };
    return validate_cmd.run(arena, io, stderr, stdout, manifest_path);
}

fn runSync(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const project_root = (try parseSyncProjectRoot(arena, stderr, args)) orelse {
        try help.printSyncUsage(stdout);
        try stdout.flush();
        return;
    };
    return sync_cmd.run(arena, io, stderr, stdout, project_root);
}

fn runAdd(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed = (try parseAddArgs(arena, stderr, args)) orelse {
        try help.printAddUsage(stdout);
        try stdout.flush();
        return;
    };
    return add_cmd.run(arena, io, stderr, stdout, parsed.source, parsed.project_root);
}

fn parseValidateArgs(allocator: std.mem.Allocator, stderr: *Io.Writer, args: []const []const u8) !?[]const u8 {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var parsed = clap.parseEx(clap.Help, &validate_params, validate_parsers, &iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.InvalidArguments;
    };
    defer parsed.deinit();
    if (parsed.args.help != 0) return null;
    return parsed.positionals[0] orelse {
        try stderr.writeAll("error: plugin validate expects <wizig-plugin.json>\n");
        try stderr.flush();
        return error.InvalidArguments;
    };
}

pub fn parseSyncProjectRoot(allocator: std.mem.Allocator, stderr: *Io.Writer, args: []const []const u8) !?[]const u8 {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var parsed = clap.parseEx(clap.Help, &sync_params, sync_parsers, &iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.InvalidArguments;
    };
    defer parsed.deinit();
    if (parsed.args.help != 0) return null;
    return parsed.positionals[0] orelse ".";
}

pub fn parseAddArgs(allocator: std.mem.Allocator, stderr: *Io.Writer, args: []const []const u8) !?AddArgs {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var parsed = clap.parseEx(clap.Help, &add_params, add_parsers, &iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.InvalidArguments;
    };
    defer parsed.deinit();
    if (parsed.args.help != 0) return null;

    const source = parsed.positionals[0] orelse {
        try stderr.writeAll("error: plugin add expects <git_or_path> [project_root]\n");
        try stderr.flush();
        return error.InvalidArguments;
    };
    return .{ .source = source, .project_root = parsed.positionals[1] orelse "." };
}
