//! `wizig wizigd` daemon command for persistent incremental codegen.
const std = @import("std");
const Io = std.Io;

const path_util = @import("../../support/path.zig");
const fs_util = @import("../../support/fs.zig");
const codegen_cache = @import("../../support/codegen_cache.zig");
const codegen_cmd = @import("../codegen/root.zig");

const DaemonCommand = enum {
    start,
    serve,
    stop,
    status,
};

const Options = struct {
    command: DaemonCommand = .status,
    project_root: []const u8 = ".",
    interval_ms: i64 = 700,
};

/// Runs daemon lifecycle commands.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const options = parseOptions(args, stderr) catch {
        try printUsage(stderr);
        try stderr.flush();
        return error.InvalidArguments;
    };
    const project_root = try path_util.resolveAbsolute(arena, io, options.project_root);

    switch (options.command) {
        .start => try startDaemon(arena, io, stderr, stdout, project_root, options.interval_ms),
        .serve => try serveDaemon(arena, io, stderr, stdout, project_root, options.interval_ms),
        .stop => try stopDaemon(arena, io, stderr, stdout, project_root),
        .status => try statusDaemon(arena, io, stdout, project_root),
    }
}

/// Writes usage help for daemon command.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Wizigd:\n" ++
            "  wizig wizigd [status] [project_root]\n" ++
            "  wizig wizigd start [project_root] [--interval-ms <ms>]\n" ++
            "  wizig wizigd serve [project_root] [--interval-ms <ms>]\n" ++
            "  wizig wizigd stop [project_root]\n" ++
            "\n",
    );
}

fn parseOptions(args: []const []const u8, stderr: *Io.Writer) !Options {
    var options = Options{};

    var i: usize = 0;
    if (i < args.len) {
        const first = args[i];
        if (std.mem.eql(u8, first, "start")) {
            options.command = .start;
            i += 1;
        } else if (std.mem.eql(u8, first, "serve")) {
            options.command = .serve;
            i += 1;
        } else if (std.mem.eql(u8, first, "stop")) {
            options.command = .stop;
            i += 1;
        } else if (std.mem.eql(u8, first, "status")) {
            options.command = .status;
            i += 1;
        }
    }

    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
        options.project_root = args[i];
        i += 1;
    }

    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--interval-ms")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --interval-ms\n");
                return error.InvalidArguments;
            }
            options.interval_ms = parseInterval(args[i + 1], stderr) catch return error.InvalidArguments;
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--interval-ms=")) {
            options.interval_ms = parseInterval(arg["--interval-ms=".len..], stderr) catch return error.InvalidArguments;
            i += 1;
            continue;
        }

        try stderr.print("error: unknown wizigd option '{s}'\n", .{arg});
        return error.InvalidArguments;
    }

    return options;
}

fn parseInterval(raw: []const u8, stderr: *Io.Writer) !i64 {
    const parsed = std.fmt.parseInt(i64, raw, 10) catch {
        try stderr.print("error: invalid interval value '{s}'\n", .{raw});
        return error.InvalidArguments;
    };
    if (parsed < 100) {
        try stderr.writeAll("error: --interval-ms must be at least 100\n");
        return error.InvalidArguments;
    }
    return parsed;
}

fn startDaemon(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    interval_ms: i64,
) !void {
    const pid_path = try daemonPidPath(arena, project_root);
    if (try readPid(io, pid_path)) |pid| {
        if (isPidRunning(pid)) {
            try stdout.print("wizigd already running for '{s}' (pid {d})\n", .{ project_root, pid });
            try stdout.flush();
            return;
        }
        try deleteFileIfExists(io, pid_path);
    }

    const exe_path = std.process.executablePathAlloc(io, arena) catch |err| {
        try stderr.print("error: failed to resolve wizig executable path: {s}\n", .{@errorName(err)});
        return error.DaemonFailed;
    };

    var interval_buf: [32]u8 = undefined;
    const interval_text = try std.fmt.bufPrint(&interval_buf, "{d}", .{interval_ms});
    var child = std.process.spawn(io, .{
        .argv = &.{ exe_path, "wizigd", "serve", project_root, "--interval-ms", interval_text },
        .pgid = 0,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch |err| {
        try stderr.print("error: failed to spawn wizigd: {s}\n", .{@errorName(err)});
        return error.DaemonFailed;
    };
    const pid = child.id orelse {
        try stderr.writeAll("error: failed to capture daemon pid\n");
        return error.DaemonFailed;
    };
    try writePid(io, pid_path, pid);

    try stdout.print("started wizigd for '{s}' (pid {d}, interval {d}ms)\n", .{ project_root, pid, interval_ms });
    try stdout.flush();
}

fn serveDaemon(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    interval_ms: i64,
) !void {
    const pid_path = try daemonPidPath(arena, project_root);
    const self_pid = std.posix.system.getpid();
    try writePid(io, pid_path, self_pid);

    try stdout.print("wizigd serving '{s}' (interval {d}ms)\n", .{ project_root, interval_ms });
    try stdout.flush();

    while (true) {
        var iter_arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer iter_arena_state.deinit();
        const iter_arena = iter_arena_state.allocator();

        const contract = codegen_cmd.resolveApiContract(iter_arena, io, stderr, project_root, null) catch |err| {
            try stderr.print("warning: wizigd failed to resolve API contract: {s}\n", .{@errorName(err)});
            try stderr.flush();
            std.Io.sleep(io, .fromMilliseconds(interval_ms), .awake) catch {};
            continue;
        };

        _ = codegen_cmd.ensureProjectGenerated(
            iter_arena,
            io,
            stderr,
            stdout,
            project_root,
            if (contract) |resolved| resolved.path else null,
            .{ .emit_skip_message = false },
        ) catch |err| {
            try stderr.print("warning: wizigd codegen iteration failed: {s}\n", .{@errorName(err)});
            try stderr.flush();
        };

        std.Io.sleep(io, .fromMilliseconds(interval_ms), .awake) catch {};
    }
}

fn stopDaemon(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
) !void {
    const pid_path = try daemonPidPath(arena, project_root);
    const pid = (try readPid(io, pid_path)) orelse {
        try stdout.print("wizigd is not running for '{s}'\n", .{project_root});
        try stdout.flush();
        return;
    };

    std.posix.kill(pid, .TERM) catch |err| switch (err) {
        error.ProcessNotFound => {
            try deleteFileIfExists(io, pid_path);
            try stdout.print("wizigd was not running for '{s}' (removed stale pid)\n", .{project_root});
            try stdout.flush();
            return;
        },
        error.PermissionDenied => {
            try stderr.print("error: permission denied stopping pid {d}\n", .{pid});
            return error.DaemonFailed;
        },
        else => return err,
    };

    var attempts: usize = 0;
    while (attempts < 20 and isPidRunning(pid)) : (attempts += 1) {
        std.Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
    }
    if (isPidRunning(pid)) {
        try stderr.print("error: wizigd pid {d} is still running after TERM\n", .{pid});
        return error.DaemonFailed;
    }
    try deleteFileIfExists(io, pid_path);
    try stdout.print("stopped wizigd for '{s}' (pid {d})\n", .{ project_root, pid });
    try stdout.flush();
}

fn statusDaemon(
    arena: std.mem.Allocator,
    io: std.Io,
    stdout: *Io.Writer,
    project_root: []const u8,
) !void {
    const pid_path = try daemonPidPath(arena, project_root);
    const pid = try readPid(io, pid_path);
    if (pid) |value| {
        if (isPidRunning(value)) {
            try stdout.print("wizigd: running (pid {d})\n", .{value});
        } else {
            try stdout.print("wizigd: stale pid file (pid {d})\n", .{value});
        }
    } else {
        try stdout.writeAll("wizigd: stopped\n");
    }

    if (try codegen_cache.readManifest(arena, io, project_root)) |manifest| {
        try stdout.print(
            "codegen manifest: fingerprint={s} inputs={d} updated_ms={d}\n",
            .{ manifest.fingerprint, manifest.lib_source_count, manifest.generated_at_unix_ms },
        );
    } else {
        try stdout.writeAll("codegen manifest: missing\n");
    }
    try stdout.flush();
}

fn daemonPidPath(arena: std.mem.Allocator, project_root: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        arena,
        "{s}{s}.wizig{s}cache{s}wizigd.pid",
        .{ project_root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );
}

fn writePid(io: std.Io, pid_path: []const u8, pid: std.posix.pid_t) !void {
    var pid_buf: [32]u8 = undefined;
    const pid_text = try std.fmt.bufPrint(&pid_buf, "{d}\n", .{pid});
    try fs_util.writeFileAtomically(io, pid_path, pid_text);
}

fn readPid(io: std.Io, pid_path: []const u8) !?std.posix.pid_t {
    const raw = std.Io.Dir.cwd().readFileAlloc(io, pid_path, std.heap.page_allocator, .limited(128)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer std.heap.page_allocator.free(raw);

    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    const parsed = std.fmt.parseInt(i64, trimmed, 10) catch return null;
    if (parsed <= 0) return null;
    return @intCast(parsed);
}

fn isPidRunning(pid: std.posix.pid_t) bool {
    const rc = std.posix.system.kill(pid, @enumFromInt(0));
    return switch (std.posix.errno(rc)) {
        .SUCCESS => true,
        .PERM => true,
        .SRCH => false,
        else => false,
    };
}

fn deleteFileIfExists(io: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

test "parseOptions supports default status and interval" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const defaults = try parseOptions(&.{}, &err_writer.writer);
    try std.testing.expectEqual(.status, defaults.command);
    try std.testing.expectEqualStrings(".", defaults.project_root);

    const parsed = try parseOptions(
        &.{ "start", "/tmp/MyApp", "--interval-ms", "400" },
        &err_writer.writer,
    );
    try std.testing.expectEqual(.start, parsed.command);
    try std.testing.expectEqualStrings("/tmp/MyApp", parsed.project_root);
    try std.testing.expectEqual(@as(i64, 400), parsed.interval_ms);
}
