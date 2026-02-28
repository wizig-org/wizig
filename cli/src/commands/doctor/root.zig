//! `wizig doctor` diagnostics for host tools and bundled assets.
const std = @import("std");
const Io = std.Io;
const sdk_locator = @import("../../support/sdk_locator.zig");
const process_util = @import("../../support/process.zig");

/// Runs environment diagnostics and SDK integrity checks.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    var explicit_sdk_root: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--sdk-root")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --sdk-root\n");
                return error.InvalidArguments;
            }
            explicit_sdk_root = args[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--sdk-root=")) {
            explicit_sdk_root = arg["--sdk-root=".len..];
            i += 1;
            continue;
        }

        try stderr.print("error: unknown doctor option '{s}'\n", .{arg});
        return error.InvalidArguments;
    }

    try stdout.writeAll("Wizig doctor\n\n");

    const tools = [_][]const u8{ "zig", "xcodegen", "xcodebuild", "xcrun", "gradle", "adb" };
    var missing: usize = 0;
    for (tools) |tool| {
        const ok = process_util.commandExists(arena, io, tool);
        try stdout.print("[{s}] {s}\n", .{ if (ok) "ok" else "missing", tool });
        if (!ok) missing += 1;
    }

    const resolved = sdk_locator.resolve(arena, io, env_map, stderr, explicit_sdk_root) catch {
        try stdout.writeAll("\n[missing] Wizig SDK bundle\n");
        return error.DoctorFailed;
    };

    try stdout.print("\n[ok] sdk_root: {s}\n", .{resolved.root});
    try stdout.print("[ok] templates: {s}\n", .{resolved.templates_dir});
    try stdout.print("[ok] runtime: {s}\n", .{resolved.runtime_dir});

    if (missing > 0) {
        try stdout.print("\nResult: warnings ({d} missing tools)\n", .{missing});
    } else {
        try stdout.writeAll("\nResult: healthy\n");
    }
    try stdout.flush();
}

/// Writes usage help for the doctor command.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Doctor:\n" ++
            "  wizig doctor [--sdk-root <path>]\n" ++
            "\n",
    );
}
