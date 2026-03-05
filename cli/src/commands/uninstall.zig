//! `wizig uninstall` — removes the wizig installation.
const std = @import("std");
const Io = std.Io;
const process = @import("../support/process.zig");

pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const options = parseOptions(args, stderr) catch {
        try stderr.flush();
        return error.InvalidArguments;
    };

    const install_root = resolveInstallRoot(arena, io) catch {
        try stderr.writeAll("error: could not determine install location\n");
        try stderr.flush();
        return error.UninstallFailed;
    };

    // Safety: refuse to uninstall from system or package-managed paths.
    if (!isUserControlledPath(install_root)) {
        try stderr.writeAll("error: wizig appears to be installed via a package manager or in a system directory\n");
        try stderr.print("  install root: {s}\n", .{install_root});
        try stderr.writeAll("hint: use your package manager to uninstall (e.g., brew uninstall wizig)\n");
        try stderr.flush();
        return error.UninstallFailed;
    }

    try stdout.print("This will remove wizig from {s}\n", .{install_root});

    if (!options.yes) {
        try stdout.writeAll("Proceed? [y/N] ");
        try stdout.flush();

        var stdin_buffer: [256]u8 = undefined;
        var file_reader = Io.File.stdin().reader(io, &stdin_buffer);
        const line = file_reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => blk: {
                if (file_reader.interface.bufferedLen() == 0) {
                    try stderr.writeAll("\nerror: no input received\n");
                    try stderr.flush();
                    return error.UninstallFailed;
                }
                break :blk file_reader.interface.buffered();
            },
            else => |e| return e,
        };
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or (trimmed[0] != 'y' and trimmed[0] != 'Y')) {
            try stdout.writeAll("Aborted.\n");
            try stdout.flush();
            return;
        }
    }

    // Remove the install directory. On both macOS and Linux, the running
    // binary's inode stays valid even after its path is unlinked, so this
    // is safe to do from within the binary itself.
    _ = process.runChecked(arena, io, stderr, null, &.{ "rm", "-rf", install_root }, null, "remove install directory") catch {
        try stderr.writeAll("error: failed to remove install directory\n");
        try stderr.flush();
        return error.UninstallFailed;
    };

    try stdout.print("Removed {s}\n", .{install_root});
    try stdout.writeAll("\nYou may want to remove the PATH entry from your shell profile (~/.zshrc, ~/.bashrc, etc.).\n");
    try stdout.writeAll("Look for and remove the line: export PATH=\"~/.wizig/bin:$PATH\"\n");
    try stdout.flush();
}

pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Uninstall:\n" ++
            "  wizig uninstall [--yes]    Remove the wizig installation\n" ++
            "\n",
    );
}

const UninstallOptions = struct {
    yes: bool = false,
};

fn parseOptions(args: []const []const u8, stderr: *Io.Writer) !UninstallOptions {
    var options = UninstallOptions{};
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--yes") or std.mem.eql(u8, arg, "-y")) {
            options.yes = true;
        } else {
            try stderr.print("error: unknown uninstall option '{s}'\n", .{arg});
            return error.InvalidArguments;
        }
    }
    return options;
}

fn resolveInstallRoot(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    const exe_path = try std.process.executablePathAlloc(io, arena);
    const exe_dir = std.fs.path.dirname(exe_path) orelse return error.PathError;
    return std.fs.path.resolve(arena, &.{ exe_dir, ".." });
}

fn isUserControlledPath(path: []const u8) bool {
    // Refuse to uninstall from system directories or Homebrew prefix.
    const blocked_prefixes = [_][]const u8{
        "/usr/",
        "/opt/homebrew/",
        "/usr/local/Cellar/",
        "/System/",
        "/bin/",
        "/sbin/",
    };
    for (blocked_prefixes) |prefix| {
        if (std.mem.startsWith(u8, path, prefix)) return false;
    }
    return true;
}

test "parseOptions accepts --yes" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const opts = try parseOptions(&.{"--yes"}, &err_writer.writer);
    try std.testing.expect(opts.yes);
}

test "parseOptions rejects unknown flag" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(
        error.InvalidArguments,
        parseOptions(&.{"--force"}, &err_writer.writer),
    );
}

test "isUserControlledPath blocks system paths" {
    try std.testing.expect(!isUserControlledPath("/usr/local/Cellar/wizig"));
    try std.testing.expect(!isUserControlledPath("/opt/homebrew/share"));
    try std.testing.expect(!isUserControlledPath("/usr/bin"));
    try std.testing.expect(isUserControlledPath("/Users/someone/.wizig"));
    try std.testing.expect(isUserControlledPath("/home/user/.wizig"));
}
