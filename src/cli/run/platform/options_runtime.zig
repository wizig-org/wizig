//! Runtime helpers for parsed `wizig run <platform>` options.
const std = @import("std");
const Io = std.Io;

const tooling = @import("tooling.zig");
const types = @import("types.zig");

/// Normalizes run options that depend on filesystem context.
pub fn normalizeRunOptions(arena: std.mem.Allocator, io: std.Io, options: types.RunOptions) !types.RunOptions {
    var normalized = options;
    normalized.project_dir = if (std.fs.path.isAbsolute(options.project_dir))
        try arena.dupe(u8, options.project_dir)
    else blk: {
        const cwd = try std.process.currentPathAlloc(io, arena);
        break :blk try std.fs.path.resolve(arena, &.{ cwd, options.project_dir });
    };
    return normalized;
}

/// Resolves iOS debugger mode with platform constraints.
pub fn resolveIosDebugger(stderr: *Io.Writer, mode: types.DebuggerMode) !types.DebuggerMode {
    return switch (mode) {
        .auto => .none,
        .lldb, .none => mode,
        else => reportInvalid(stderr, "iOS supports --debugger auto|lldb|none"),
    };
}

/// Resolves Android debugger mode and validates required host tools.
pub fn resolveAndroidDebugger(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    mode: types.DebuggerMode,
) !types.DebuggerMode {
    return switch (mode) {
        .auto => .logcat,
        .jdb => blk: {
            if (!tooling.commandExists(arena, io, "jdb")) {
                return reportInvalid(stderr, "jdb not found; use --debugger logcat|none or install JDK tools");
            }
            break :blk .jdb;
        },
        .logcat, .none => mode,
        else => reportInvalid(stderr, "Android supports --debugger auto|jdb|logcat|none"),
    };
}

/// Validates platform-specific flag combinations.
pub fn validatePlatformOptions(stderr: *Io.Writer, options: types.RunOptions) !void {
    switch (options.platform) {
        .ios => {
            if (!std.mem.eql(u8, options.module, "app")) return reportInvalid(stderr, "--module is Android-only");
            if (options.app_id != null or options.activity != null) return reportInvalid(stderr, "--app-id/--activity are Android-only");
        },
        .android => if (options.scheme != null or options.bundle_id != null) return reportInvalid(stderr, "--scheme/--bundle-id are iOS-only"),
    }
    if (options.skip_device_discovery and options.device_selector == null) {
        return reportInvalid(stderr, "--__wizig-skip-device-discovery requires --device");
    }
}

fn reportInvalid(stderr: *Io.Writer, message: []const u8) error{RunFailed} {
    stderr.writeAll("error: ") catch {};
    stderr.writeAll(message) catch {};
    stderr.writeAll("\n") catch {};
    stderr.flush() catch {};
    return error.RunFailed;
}
