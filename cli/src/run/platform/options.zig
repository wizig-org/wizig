//! Parsing and normalization for `wizig run` platform options.
//!
//! The parser enforces platform-specific flag validity and keeps all option
//! validation in one module so execution paths can assume normalized input.
const std = @import("std");
const Io = std.Io;

const tooling = @import("tooling.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

/// Parses CLI arguments into a validated `RunOptions` object.
pub fn parseRunOptions(args: []const []const u8, stderr: *Io.Writer) !types.RunOptions {
    if (args.len < 2) {
        try stderr.writeAll("error: run expects <ios|android> <project_dir> [options]\n");
        return error.RunFailed;
    }

    const platform = std.meta.stringToEnum(types.Platform, args[0]) orelse {
        try stderr.print("error: unknown platform '{s}', expected ios or android\n", .{args[0]});
        return error.RunFailed;
    };

    var options = types.RunOptions{
        .platform = platform,
        .project_dir = args[1],
    };

    var i: usize = 2;
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
        if (std.mem.eql(u8, arg, "--__wizig-skip-device-discovery")) {
            options.skip_device_discovery = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--__wizig-skip-codegen")) {
            options.skip_codegen = true;
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
            options.debugger = std.meta.stringToEnum(types.DebuggerMode, value) orelse {
                try stderr.print("error: invalid debugger mode '{s}'\n", .{value});
                return error.RunFailed;
            };
        } else if (std.mem.eql(u8, arg, "--scheme")) {
            options.scheme = value;
        } else if (std.mem.eql(u8, arg, "--bundle-id")) {
            options.bundle_id = value;
        } else if (std.mem.eql(u8, arg, "--module")) {
            options.module = value;
        } else if (std.mem.eql(u8, arg, "--app-id")) {
            options.app_id = value;
        } else if (std.mem.eql(u8, arg, "--activity")) {
            options.activity = value;
        } else {
            try stderr.print("error: unknown run option '{s}'\n", .{arg});
            return error.RunFailed;
        }
        i += 2;
    }

    switch (options.platform) {
        .ios => {
            if (options.module.len != "app".len or !std.mem.eql(u8, options.module, "app")) {
                try stderr.writeAll("error: --module is Android-only\n");
                return error.RunFailed;
            }
            if (options.app_id != null or options.activity != null) {
                try stderr.writeAll("error: --app-id/--activity are Android-only\n");
                return error.RunFailed;
            }
        },
        .android => {
            if (options.scheme != null or options.bundle_id != null) {
                try stderr.writeAll("error: --scheme/--bundle-id are iOS-only\n");
                return error.RunFailed;
            }
        },
    }

    if (options.skip_device_discovery and options.device_selector == null) {
        try stderr.writeAll("error: --__wizig-skip-device-discovery requires --device\n");
        return error.RunFailed;
    }

    return options;
}

/// Normalizes run options that depend on filesystem context.
pub fn normalizeRunOptions(arena: Allocator, io: std.Io, options: types.RunOptions) !types.RunOptions {
    var normalized = options;
    if (!std.fs.path.isAbsolute(options.project_dir)) {
        const cwd = try std.process.currentPathAlloc(io, arena);
        normalized.project_dir = try std.fs.path.resolve(arena, &.{ cwd, options.project_dir });
    } else {
        normalized.project_dir = try arena.dupe(u8, options.project_dir);
    }
    return normalized;
}

/// Resolves iOS debugger mode with platform constraints.
pub fn resolveIosDebugger(stderr: *Io.Writer, mode: types.DebuggerMode) !types.DebuggerMode {
    return switch (mode) {
        .auto => .none,
        .lldb, .none => mode,
        else => {
            try stderr.writeAll("error: iOS supports --debugger auto|lldb|none\n");
            return error.RunFailed;
        },
    };
}

/// Resolves Android debugger mode and validates required host tools.
pub fn resolveAndroidDebugger(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    mode: types.DebuggerMode,
) !types.DebuggerMode {
    return switch (mode) {
        .auto => .logcat,
        .jdb => blk: {
            if (!tooling.commandExists(arena, io, "jdb")) {
                try stderr.writeAll("error: jdb not found; use --debugger logcat|none or install JDK tools\n");
                return error.RunFailed;
            }
            break :blk .jdb;
        },
        .logcat, .none => mode,
        else => {
            try stderr.writeAll("error: Android supports --debugger auto|jdb|logcat|none\n");
            return error.RunFailed;
        },
    };
}

test "parseRunOptions parses shared and platform flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseRunOptions(&.{
        "android",
        "examples/android/WizigExample",
        "--device",
        "emulator-5554",
        "--module",
        "app",
        "--debugger",
        "none",
        "--once",
    }, &err_writer.writer);

    try std.testing.expectEqual(types.Platform.android, options.platform);
    try std.testing.expectEqualStrings("examples/android/WizigExample", options.project_dir);
    try std.testing.expectEqualStrings("emulator-5554", options.device_selector.?);
    try std.testing.expectEqual(types.DebuggerMode.none, options.debugger);
    try std.testing.expect(options.once);
    try std.testing.expect(!options.regenerate_host);
    try std.testing.expect(!options.skip_device_discovery);
}

test "parseRunOptions rejects mixed platform flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(
        error.RunFailed,
        parseRunOptions(&.{
            "ios",
            "examples/ios/WizigExample",
            "--module",
            "custom-module",
        }, &err_writer.writer),
    );
}

test "parseRunOptions parses internal skip-codegen flag" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseRunOptions(&.{
        "android",
        "examples/android/WizigExample",
        "--device",
        "emulator-5554",
        "--__wizig-skip-codegen",
    }, &err_writer.writer);

    try std.testing.expect(options.skip_codegen);
}
