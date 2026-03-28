//! `wizig self-update` — checks for and installs the latest release.
const std = @import("std");
const Io = std.Io;
const build_options = @import("build_options");
const process = @import("../support/process.zig");
const version_util = @import("../support/toolchains/version.zig");

const repo = "wizig-org/wizig";
const api_url = "https://api.github.com/repos/" ++ repo ++ "/releases/latest";

pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
) !void {
    const current = build_options.version;

    if (std.mem.eql(u8, current, "dev")) {
        try stderr.writeAll("error: self-update is not available for development builds\n");
        try stderr.writeAll("hint: install wizig via 'curl -fsSL wizig.org/install.sh | sh' or 'brew install wizig-org/tap/wizig'\n");
        try stderr.flush();
        return error.SelfUpdateFailed;
    }

    try stdout.writeAll("Checking for updates...\n");
    try stdout.flush();

    const latest = fetchLatestVersion(arena, io, stderr) catch {
        try stderr.writeAll("error: could not check for updates\n");
        try stderr.writeAll("hint: check your internet connection or try again later\n");
        try stderr.flush();
        return error.SelfUpdateFailed;
    };

    if (version_util.isAtLeast(current, latest)) {
        try stdout.print("wizig is already up to date ({s})\n", .{current});
        try stdout.flush();
        return;
    }

    try stdout.print("Updating wizig from {s} to {s}...\n", .{ current, latest });
    try stdout.flush();

    const install_root = resolveInstallRoot(arena, io) catch {
        try stderr.writeAll("error: could not determine install location\n");
        try stderr.flush();
        return error.SelfUpdateFailed;
    };

    const os_name = comptime osName();
    const arch_name = comptime archName();
    const tarball = std.fmt.allocPrint(arena, "wizig-{s}-{s}-{s}", .{ latest, os_name, arch_name }) catch
        return error.SelfUpdateFailed;
    const tarball_gz = std.fmt.allocPrint(arena, "{s}.tar.gz", .{tarball}) catch
        return error.SelfUpdateFailed;
    const url = std.fmt.allocPrint(
        arena,
        "https://github.com/{s}/releases/download/v{s}/{s}",
        .{ repo, latest, tarball_gz },
    ) catch return error.SelfUpdateFailed;

    // Download to temp directory.
    const tmpdir = std.fmt.allocPrint(arena, "/tmp/wizig-self-update-{s}", .{latest}) catch
        return error.SelfUpdateFailed;

    _ = process.runCapture(arena, io, null, &.{ "rm", "-rf", tmpdir }, null) catch {};
    _ = process.runChecked(arena, io, stderr, null, &.{ "mkdir", "-p", tmpdir }, null, "create temp directory") catch
        return error.SelfUpdateFailed;

    // Download tarball.
    _ = process.runChecked(arena, io, stderr, null, &.{
        "curl", "-fsSL", "-o",
        std.fmt.allocPrint(arena, "{s}/{s}", .{ tmpdir, tarball_gz }) catch return error.SelfUpdateFailed,
        url,
    }, null, "download release") catch
        return error.SelfUpdateFailed;

    // Extract.
    _ = process.runChecked(arena, io, stderr, tmpdir, &.{
        "tar", "xzf", tarball_gz,
    }, null, "extract release") catch
        return error.SelfUpdateFailed;

    // Copy into install root.
    const extracted = std.fmt.allocPrint(arena, "{s}/{s}/.", .{ tmpdir, tarball }) catch
        return error.SelfUpdateFailed;
    _ = process.runChecked(arena, io, stderr, null, &.{
        "cp", "-R", extracted, install_root,
    }, null, "install update") catch
        return error.SelfUpdateFailed;

    // Cleanup.
    _ = process.runCapture(arena, io, null, &.{ "rm", "-rf", tmpdir }, null) catch {};

    // Remove quarantine on macOS.
    if (comptime @import("builtin").os.tag == .macos) {
        const bin_path = std.fmt.allocPrint(arena, "{s}/bin/wizig", .{install_root}) catch
            return error.SelfUpdateFailed;
        _ = process.runCapture(arena, io, null, &.{ "xattr", "-d", "com.apple.quarantine", bin_path }, null) catch {};
    }

    try stdout.print("Updated wizig to {s}\n", .{latest});
    try stdout.flush();
}

pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Self-update:\n" ++
            "  wizig self-update    Check for and install the latest version\n" ++
            "\n",
    );
}

fn fetchLatestVersion(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]const u8 {
    const result = process.runChecked(arena, io, stderr, null, &.{
        "curl", "-fsSL", "-H", "Accept: application/vnd.github.v3+json", api_url,
    }, null, "query GitHub releases") catch return error.NetworkError;

    // Parse tag_name from JSON response (simple search, no JSON parser needed).
    const tag_prefix = "\"tag_name\":";
    const stdout_data = result.stdout;
    const tag_start = std.mem.indexOf(u8, stdout_data, tag_prefix) orelse return error.ParseError;
    const after_prefix = stdout_data[tag_start + tag_prefix.len ..];

    // Skip whitespace and opening quote.
    var idx: usize = 0;
    while (idx < after_prefix.len and (after_prefix[idx] == ' ' or after_prefix[idx] == '"')) : (idx += 1) {}

    // Skip leading 'v' if present.
    if (idx < after_prefix.len and after_prefix[idx] == 'v') idx += 1;

    const version_start = idx;
    while (idx < after_prefix.len and after_prefix[idx] != '"') : (idx += 1) {}

    if (idx == version_start) return error.ParseError;
    return arena.dupe(u8, after_prefix[version_start..idx]);
}

fn resolveInstallRoot(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    const exe_path = try std.process.executablePathAlloc(io, arena);
    const exe_dir = std.fs.path.dirname(exe_path) orelse return error.PathError;
    return std.fs.path.resolve(arena, &.{ exe_dir, ".." });
}

fn osName() []const u8 {
    return switch (@import("builtin").os.tag) {
        .macos => "macos",
        .linux => "linux",
        else => @compileError("unsupported OS for self-update"),
    };
}

fn archName() []const u8 {
    return switch (@import("builtin").cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x86_64",
        else => @compileError("unsupported architecture for self-update"),
    };
}
