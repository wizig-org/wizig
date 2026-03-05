//! `wizig build` command handler.
//!
//! Currently supports:
//!   wizig build android --release [--abis arm64-v8a,armeabi-v7a,x86_64]

const std = @import("std");
const Io = std.Io;

const android_multi_abi = @import("android_multi_abi.zig");
const android_release_build = @import("android_release_build.zig");

pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    if (args.len == 0) {
        try printUsage(stderr);
        return error.BuildFailed;
    }

    const subcommand = args[0];
    const rest = args[1..];

    if (std.mem.eql(u8, subcommand, "android")) {
        try runAndroid(arena, io, stderr, stdout, rest);
        return;
    }

    try stderr.print("error: unknown build subcommand: {s}\n\n", .{subcommand});
    try printUsage(stderr);
    try stderr.flush();
    return error.BuildFailed;
}

fn runAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    var is_release = false;
    var custom_abis: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--release")) {
            is_release = true;
        } else if (std.mem.eql(u8, args[i], "--abis")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("error: --abis requires a comma-separated list of ABIs\n");
                return error.BuildFailed;
            }
            custom_abis = args[i];
        }
    }

    if (!is_release) {
        try stderr.writeAll("error: `wizig build android` currently requires --release\n");
        return error.BuildFailed;
    }

    // Parse ABI list
    var abis = std.ArrayList([]const u8).empty;
    if (custom_abis) |abi_str| {
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
        "Build commands:\n" ++
            "  wizig build android --release [--abis arm64-v8a,armeabi-v7a,x86_64]\n" ++
            "    Build multi-ABI release for Play Store distribution.\n\n",
    );
}

test "printUsage includes build android" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    const output = out_writer.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig build android") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--release") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--abis") != null);
}
