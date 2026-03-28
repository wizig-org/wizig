//! Unified run option parsing and root resolution.
//!
//! This module keeps argument parsing deterministic and separate from discovery
//! and delegation logic.
const std = @import("std");
const Io = std.Io;

const types = @import("types.zig");

/// Parses unified run options from CLI args.
pub fn parseUnifiedOptions(args: []const []const u8, stderr: *Io.Writer) !types.UnifiedOptions {
    var options = types.UnifiedOptions{};

    var i: usize = 0;
    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
        options.project_root = args[i];
        i += 1;
    }

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--non-interactive")) {
            options.non_interactive = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--once")) {
            options.once = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--regenerate-host")) {
            options.regenerate_host = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--allow-toolchain-drift")) {
            options.allow_toolchain_drift = true;
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--monitor-timeout=")) {
            const raw = arg["--monitor-timeout=".len..];
            options.monitor_timeout_seconds = try parseMonitorTimeout(raw, stderr);
            i += 1;
            continue;
        }

        if (i + 1 >= args.len) {
            try stderr.print("error: missing value for option '{s}'\n", .{arg});
            return error.RunFailed;
        }

        const value = args[i + 1];
        if (std.mem.eql(u8, arg, "--device")) {
            options.device_selector = value;
        } else if (std.mem.eql(u8, arg, "--debugger")) {
            options.debugger_mode = value;
        } else if (std.mem.eql(u8, arg, "--monitor-timeout")) {
            options.monitor_timeout_seconds = try parseMonitorTimeout(value, stderr);
        } else {
            try stderr.print("error: unknown run option '{s}'\n", .{arg});
            return error.RunFailed;
        }
        i += 2;
    }

    return options;
}

/// Parses monitor timeout seconds from CLI input.
fn parseMonitorTimeout(raw: []const u8, stderr: *Io.Writer) !u64 {
    const seconds = std.fmt.parseInt(u64, raw, 10) catch {
        try stderr.print("error: invalid --monitor-timeout value '{s}' (expected positive integer seconds)\n", .{raw});
        return error.RunFailed;
    };
    if (seconds == 0) {
        try stderr.writeAll("error: --monitor-timeout must be greater than zero seconds\n");
        return error.RunFailed;
    }
    return seconds;
}

/// Resolves project root to an absolute path.
pub fn resolveProjectRoot(arena: std.mem.Allocator, io: std.Io, root: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(root)) {
        return arena.dupe(u8, root);
    }
    const cwd = try std.process.currentPathAlloc(io, arena);
    return std.fs.path.resolve(arena, &.{ cwd, root });
}

test "parseUnifiedOptions defaults" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseUnifiedOptions(&.{}, &err_writer.writer);
    try std.testing.expectEqualStrings(".", options.project_root);
    try std.testing.expect(options.device_selector == null);
    try std.testing.expect(options.debugger_mode == null);
    try std.testing.expect(options.monitor_timeout_seconds == null);
    try std.testing.expect(!options.non_interactive);
    try std.testing.expect(!options.once);
    try std.testing.expect(!options.regenerate_host);
    try std.testing.expect(!options.allow_toolchain_drift);
}

test "parseUnifiedOptions parses project and flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseUnifiedOptions(
        &.{ "examples/app/WizigExample", "--device", "emulator-5554", "--debugger", "none", "--monitor-timeout", "75", "--once", "--regenerate-host", "--allow-toolchain-drift" },
        &err_writer.writer,
    );
    try std.testing.expectEqualStrings("examples/app/WizigExample", options.project_root);
    try std.testing.expectEqualStrings("emulator-5554", options.device_selector.?);
    try std.testing.expectEqualStrings("none", options.debugger_mode.?);
    try std.testing.expectEqual(@as(?u64, 75), options.monitor_timeout_seconds);
    try std.testing.expect(options.once);
    try std.testing.expect(options.regenerate_host);
    try std.testing.expect(options.allow_toolchain_drift);
}

test "parseUnifiedOptions parses inline monitor timeout form" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseUnifiedOptions(
        &.{"--monitor-timeout=30"},
        &err_writer.writer,
    );
    try std.testing.expectEqual(@as(?u64, 30), options.monitor_timeout_seconds);
}
