//! Android debugger and log-monitor attachment helpers.
//!
//! This module handles jdb attachment setup and PID/JDWP polling used by both
//! debugger and filtered logcat execution paths.
const std = @import("std");
const Io = std.Io;

const process = @import("process_supervisor.zig");
const text_utils = @import("text_utils.zig");

/// Attaches `jdb` to the target Android app via adb JDWP forwarding.
pub fn attachJdb(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    serial: []const u8,
    app_id: []const u8,
) !void {
    try stdout.writeAll("waiting for Android debug process...\n");
    try stdout.flush();

    const pid = try waitForAndroidPid(io, stderr, serial, app_id);
    try waitForJdwpPid(io, stderr, serial, pid);
    const port = try setupAdbForward(io, stderr, serial, pid);

    var forward_buf: [24]u8 = undefined;
    const forward_name = try std.fmt.bufPrint(&forward_buf, "tcp:{d}", .{port});
    defer {
        _ = process.runCapture(arena, io, .{
            .argv = &.{ "adb", "-s", serial, "forward", "--remove", forward_name },
            .label = "remove adb JDWP forwarding",
        }, .{}) catch {};
    }

    var attach_buf: [32]u8 = undefined;
    const attach_target = try std.fmt.bufPrint(&attach_buf, "localhost:{d}", .{port});

    try stdout.print("attaching jdb to pid {d} on {s} (type `run` in jdb if app is waiting)...\n", .{ pid, attach_target });
    try stdout.flush();
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "jdb", "-attach", attach_target },
        .label = "attach jdb",
    });
}

/// Waits for an Android app PID to become visible via `pidof`.
pub fn waitForAndroidPid(
    io: std.Io,
    stderr: *Io.Writer,
    serial: []const u8,
    app_id: []const u8,
) !u32 {
    var attempt: usize = 0;
    while (attempt < 120) : (attempt += 1) {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        const result = process.runCapture(scratch, io, .{
            .argv = &.{ "adb", "-s", serial, "shell", "pidof", app_id },
            .label = "wait for Android PID",
        }, .{}) catch {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        };
        if (!process.termIsSuccess(result.term)) {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        }
        if (text_utils.parseFirstIntToken(u32, result.stdout)) |pid| return pid;
        std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
    }

    try stderr.writeAll("error: timed out waiting for Android app PID\n");
    return error.RunFailed;
}

fn waitForJdwpPid(io: std.Io, stderr: *Io.Writer, serial: []const u8, pid: u32) !void {
    var attempt: usize = 0;
    while (attempt < 120) : (attempt += 1) {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        const result = process.runCapture(scratch, io, .{
            .argv = &.{ "adb", "-s", serial, "jdwp" },
            .label = "wait for Android JDWP endpoint",
        }, .{}) catch {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        };
        if (process.termIsSuccess(result.term) and text_utils.hasPidLine(result.stdout, pid)) return;
        std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
    }
    try stderr.writeAll("error: timed out waiting for JDWP endpoint\n");
    return error.RunFailed;
}

fn setupAdbForward(io: std.Io, stderr: *Io.Writer, serial: []const u8, pid: u32) !u16 {
    var port: u16 = 8700;
    while (port < 8800) : (port += 1) {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        var tcp_buf: [24]u8 = undefined;
        var jdwp_buf: [24]u8 = undefined;
        const tcp_name = try std.fmt.bufPrint(&tcp_buf, "tcp:{d}", .{port});
        const jdwp_name = try std.fmt.bufPrint(&jdwp_buf, "jdwp:{d}", .{pid});

        const result = process.runCapture(scratch, io, .{
            .argv = &.{ "adb", "-s", serial, "forward", tcp_name, jdwp_name },
            .label = "setup adb JDWP forwarding",
        }, .{}) catch continue;
        if (process.termIsSuccess(result.term)) return port;
    }

    try stderr.writeAll("error: failed to reserve local JDWP forwarding port\n");
    return error.RunFailed;
}
