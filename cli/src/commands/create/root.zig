//! `wizig create` command parser and dispatch.
const std = @import("std");
const Io = std.Io;
const scaffold = @import("scaffold.zig");

/// Parses create options and delegates scaffold generation.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const request = parseCreateRequest(args, stderr) catch {
        try stderr.flush();
        return error.CreateFailed;
    };

    try scaffold.createApp(
        arena,
        io,
        env_map,
        stderr,
        stdout,
        request.app_name,
        request.destination_dir,
        request.platforms,
        request.sdk_root,
    );
}

/// Writes usage help for the create command.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Create:\n" ++
            "  wizig create <name> [destination_dir] [--platforms ios,android,macos] [--sdk-root <path>]\n" ++
            "\n",
    );
}

const CreateRequest = struct {
    app_name: []const u8,
    destination_dir: []const u8,
    platforms: scaffold.CreatePlatforms,
    sdk_root: ?[]const u8,
};

fn parseCreateRequest(args: []const []const u8, stderr: *Io.Writer) !CreateRequest {
    if (args.len == 0) {
        try stderr.writeAll("error: create expects <name> [destination_dir] [--platforms ...] [--sdk-root <path>]\n");
        return error.InvalidArguments;
    }

    var index: usize = 0;
    const app_name = args[index];
    index += 1;

    var destination_dir = app_name;
    if (index < args.len and !isOptionArg(args[index])) {
        destination_dir = args[index];
        index += 1;
    }

    var platforms = scaffold.CreatePlatforms{};
    var sdk_root: ?[]const u8 = null;

    while (index < args.len) {
        const arg = args[index];

        if (std.mem.eql(u8, arg, "--platforms")) {
            if (index + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --platforms\n");
                return error.InvalidArguments;
            }
            platforms = try parseCreatePlatforms(args[index + 1], stderr);
            index += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--platforms=")) {
            platforms = try parseCreatePlatforms(arg["--platforms=".len..], stderr);
            index += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--sdk-root")) {
            if (index + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --sdk-root\n");
                return error.InvalidArguments;
            }
            sdk_root = args[index + 1];
            index += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--sdk-root=")) {
            sdk_root = arg["--sdk-root=".len..];
            index += 1;
            continue;
        }

        try stderr.print("error: unknown create option '{s}'\n", .{arg});
        return error.InvalidArguments;
    }

    if (!hasAnyCreatePlatform(platforms)) {
        try stderr.writeAll("error: at least one platform must be selected\n");
        return error.InvalidArguments;
    }

    return .{
        .app_name = app_name,
        .destination_dir = destination_dir,
        .platforms = platforms,
        .sdk_root = sdk_root,
    };
}

fn parseCreatePlatforms(raw: []const u8, stderr: *Io.Writer) !scaffold.CreatePlatforms {
    var platforms = scaffold.CreatePlatforms{
        .ios = false,
        .android = false,
        .macos = false,
    };

    var parts = std.mem.splitScalar(u8, raw, ',');
    while (parts.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t\r\n");
        if (part.len == 0) continue;

        if (std.mem.eql(u8, part, "ios")) {
            platforms.ios = true;
            continue;
        }
        if (std.mem.eql(u8, part, "android")) {
            platforms.android = true;
            continue;
        }
        if (std.mem.eql(u8, part, "macos")) {
            platforms.macos = true;
            continue;
        }
        if (std.mem.eql(u8, part, "mobile")) {
            platforms.ios = true;
            platforms.android = true;
            continue;
        }
        if (std.mem.eql(u8, part, "all")) {
            platforms.ios = true;
            platforms.android = true;
            platforms.macos = true;
            continue;
        }

        try stderr.print("error: unsupported platform '{s}' in --platforms\n", .{part});
        return error.InvalidArguments;
    }

    if (!hasAnyCreatePlatform(platforms)) {
        try stderr.writeAll("error: --platforms must include at least one platform\n");
        return error.InvalidArguments;
    }

    return platforms;
}

fn hasAnyCreatePlatform(platforms: scaffold.CreatePlatforms) bool {
    return platforms.ios or platforms.android or platforms.macos;
}

fn isOptionArg(arg: []const u8) bool {
    return std.mem.startsWith(u8, arg, "--");
}
