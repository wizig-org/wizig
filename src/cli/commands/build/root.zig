//! `wizig build` command handler.
//!
//! Currently supports:
//!   wizig build android --release [--abis arm64-v8a,armeabi-v7a,x86_64]

const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

const android_multi_abi = @import("android_multi_abi.zig");
const android_release_build = @import("android_release_build.zig");
const clap_support = @import("../../support/clap_support.zig");

const BuildCommand = enum { android };
const build_parsers = .{ .COMMAND = clap.parsers.enumeration(BuildCommand) };

const build_params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit.
    \\<COMMAND>     Build target to execute.
    \\
);

const android_params = clap.parseParamsComptime(
    \\-h, --help        Display this help and exit.
    \\    --release     Build the Android release artifacts.
    \\    --abis <abis> Comma-separated ABI list override.
    \\
);
const android_parsers = .{
    .abis = clap.parsers.string,
};

pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed = try parseBuildArgs(arena, stderr, args);
    if (parsed == null) {
        if (args.len > 0 and std.mem.eql(u8, args[0], "android")) {
            try printAndroidUsage(stdout);
        } else {
            try printUsage(stdout);
        }
        try stdout.flush();
        return;
    }
    try runAndroid(arena, io, stderr, stdout, parsed.?);
}

fn runAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: AndroidBuildArgs,
) !void {
    if (!options.release) {
        try stderr.writeAll("error: `wizig build android` currently requires --release\n");
        return error.BuildFailed;
    }

    var abis = std.ArrayList([]const u8).empty;
    if (options.abis) |abi_str| {
        var it = std.mem.tokenizeScalar(u8, abi_str, ',');
        while (it.next()) |token| {
            const trimmed = std.mem.trim(u8, token, " \t");
            if (trimmed.len > 0) {
                try abis.append(arena, trimmed);
            }
        }
    } else {
        try abis.appendSlice(arena, android_multi_abi.release_abis);
    }

    if (abis.items.len == 0) {
        try stderr.writeAll("error: no ABIs specified\n");
        return error.BuildFailed;
    }

    const cwd = try std.process.currentPathAlloc(io, arena);

    try android_release_build.runAndroidReleaseBuild(
        arena,
        io,
        stderr,
        stdout,
        cwd,
        abis.items,
    );
}

pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Build:\n" ++
            "  wizig build <command>\n\n" ++
            "Options:\n" ++
            "  -h, --help    Display this help and exit.\n\n" ++
            "Commands:\n" ++
            "  android       Build multi-ABI Android release artifacts for Play Store distribution.\n\n" ++
            "Run `wizig build android --help` for command-specific usage.\n",
    );
}

/// Writes `wizig build android` usage and option help.
fn printAndroidUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Build Android:\n" ++
            "  wizig build android --release [--abis <abis>]\n\n" ++
            "Options:\n" ++
            "  -h, --help       Display this help and exit.\n" ++
            "      --release    Build the Android release artifacts.\n" ++
            "      --abis <abis>\n" ++
            "                   Comma-separated ABI list override.\n",
    );
}

const AndroidBuildArgs = struct {
    release: bool,
    abis: ?[]const u8,
};

fn parseBuildArgs(
    arena: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?AndroidBuildArgs {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var result = clap.parseEx(clap.Help, &build_params, build_parsers, &iter, .{
        .allocator = arena,
        .diagnostic = &diag,
        .terminating_positional = 0,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.BuildFailed;
    };
    defer result.deinit();

    if (result.args.help != 0) return null;
    const command = result.positionals[0] orelse {
        try stderr.writeAll("error: build expects a subcommand\n");
        try stderr.flush();
        return error.BuildFailed;
    };

    return switch (command) {
        .android => try parseAndroidArgs(arena, stderr, iter.remaining()),
    };
}

fn parseAndroidArgs(
    arena: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?AndroidBuildArgs {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var result = clap.parseEx(clap.Help, &android_params, android_parsers, &iter, .{
        .allocator = arena,
        .diagnostic = &diag,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.BuildFailed;
    };
    defer result.deinit();

    if (result.args.help != 0) return null;
    return .{
        .release = result.args.release != 0,
        .abis = result.args.abis,
    };
}

test "printUsage covers build summaries" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    const output = out_writer.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig build <command>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig build android --help") != null);
}

test "parseBuildArgs parses android release settings" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const parsed = (try parseBuildArgs(
        std.testing.allocator,
        &err_writer.writer,
        &.{ "android", "--release", "--abis=arm64-v8a,x86_64" },
    )).?;
    try std.testing.expect(parsed.release);
    try std.testing.expectEqualStrings("arm64-v8a,x86_64", parsed.abis.?);
}
