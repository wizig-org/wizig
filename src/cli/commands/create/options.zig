//! `wizig create` argument parsing and validation.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

const scaffold = @import("scaffold.zig");
const clap_support = @import("../../support/clap_support.zig");

/// Parsed `wizig create` request values.
pub const CreateRequest = struct {
    app_name: []const u8,
    destination_dir: []const u8,
    platforms: scaffold.CreatePlatforms,
    sdk_root: ?[]const u8,
    force_host_overwrite: bool,
};

const parsers = .{
    .NAME = clap.parsers.string,
    .DESTINATION_DIR = clap.parsers.string,
    .PATH = clap.parsers.string,
    .PLATFORMS = clap.parsers.string,
};

const params = clap.parseParamsComptime(
    \\-h, --help                    Display this help and exit.
    \\    --platforms <PLATFORMS>   Target platforms to scaffold.
    \\    --sdk-root <PATH>         Explicit Wizig SDK bundle root.
    \\    --force-host-overwrite    Overwrite managed host files when needed.
    \\<NAME>                        App name to scaffold.
    \\<DESTINATION_DIR>             Destination directory override.
    \\
);

/// Parses CLI arguments into a scaffold request or `null` for `--help`.
pub fn parseCreateRequest(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?CreateRequest {
    var normalized = std.ArrayList([]const u8).empty;
    defer normalized.deinit(allocator);
    try normalized.ensureTotalCapacity(allocator, args.len);
    for (args) |arg| {
        normalized.appendAssumeCapacity(if (std.mem.eql(u8, arg, "--force")) "--force-host-overwrite" else arg);
    }

    var iter = clap_support.SliceIterator.init(normalized.items);
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
    const app_name = result.positionals[0] orelse {
        try stderr.writeAll("error: create expects <name>\n");
        try stderr.flush();
        return error.InvalidArguments;
    };

    const platforms = if (result.args.platforms) |raw|
        try parseCreatePlatforms(raw, stderr)
    else
        scaffold.CreatePlatforms{ .ios = true, .android = true, .macos = false };
    return .{
        .app_name = app_name,
        .destination_dir = result.positionals[1] orelse app_name,
        .platforms = platforms,
        .sdk_root = @field(result.args, "sdk-root"),
        .force_host_overwrite = @field(result.args, "force-host-overwrite") != 0,
    };
}

/// Writes `wizig create` usage with optional destination semantics.
pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Create:\n" ++
            "  wizig create <name> [destination_dir] [options]\n\n" ++
            "Options:\n" ++
            "  -h, --help                   Display this help and exit.\n" ++
            "      --platforms <PLATFORMS>  Target platforms to scaffold.\n" ++
            "      --sdk-root <PATH>        Explicit Wizig SDK bundle root.\n" ++
            "      --force-host-overwrite   Overwrite managed host files when needed.\n\n" ++
            "Arguments:\n" ++
            "  <name>                       App name to scaffold.\n" ++
            "  [destination_dir]            Destination directory override. Defaults to <name>.\n\n" ++
            "Aliases:\n" ++
            "  --force == --force-host-overwrite\n",
    );
}

fn parseCreatePlatforms(raw: []const u8, stderr: *Io.Writer) !scaffold.CreatePlatforms {
    var platforms = scaffold.CreatePlatforms{};
    var parts = std.mem.splitScalar(u8, raw, ',');
    while (parts.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t\r\n");
        if (part.len == 0) continue;
        if (std.mem.eql(u8, part, "ios")) platforms.ios = true else if (std.mem.eql(u8, part, "android")) platforms.android = true else if (std.mem.eql(u8, part, "macos")) platforms.macos = true else if (std.mem.eql(u8, part, "mobile")) {
            platforms.ios = true;
            platforms.android = true;
        } else if (std.mem.eql(u8, part, "all")) {
            platforms.ios = true;
            platforms.android = true;
            platforms.macos = true;
        } else {
            try stderr.print("error: unsupported platform '{s}' in --platforms\n", .{part});
            try stderr.flush();
            return error.InvalidArguments;
        }
    }
    if (!platforms.ios and !platforms.android and !platforms.macos) {
        try stderr.writeAll("error: --platforms must include at least one platform\n");
        try stderr.flush();
        return error.InvalidArguments;
    }
    return platforms;
}

test "parseCreateRequest defaults destination and force flag" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const request = (try parseCreateRequest(std.testing.allocator, &err_writer.writer, &.{"DemoApp"})).?;
    try std.testing.expectEqualStrings("DemoApp", request.app_name);
    try std.testing.expectEqualStrings("DemoApp", request.destination_dir);
    try std.testing.expect(!request.force_host_overwrite);
    try std.testing.expect(request.platforms.ios and request.platforms.android);
    try std.testing.expect(!request.platforms.macos);
}

test "parseCreateRequest accepts explicit platforms and force alias" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const request = (try parseCreateRequest(
        std.testing.allocator,
        &err_writer.writer,
        &.{ "DemoApp", "out/DemoApp", "--platforms=mobile", "--force" },
    )).?;
    try std.testing.expectEqualStrings("out/DemoApp", request.destination_dir);
    try std.testing.expect(request.force_host_overwrite);
    try std.testing.expect(request.platforms.ios and request.platforms.android);
    try std.testing.expect(!request.platforms.macos);
}

test "printUsage documents optional destination dir" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    try std.testing.expect(std.mem.indexOf(u8, out_writer.writer.buffered(), "[destination_dir]") != null);
}
