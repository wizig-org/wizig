//! clap-backed parsing for platform-specific run options.
const std = @import("std");
const Io = std.Io;
const clap = @import("clap");

const clap_support = @import("../../support/clap_support.zig");
const types = @import("types.zig");

const parsers = .{
    .PLATFORM = clap.parsers.string,
    .PROJECT_DIR = clap.parsers.string,
    .DEVICE = clap.parsers.string,
    .DEBUGGER = clap.parsers.string,
    .SECONDS = clap.parsers.string,
    .SCHEME = clap.parsers.string,
    .BUNDLE_ID = clap.parsers.string,
    .MODULE = clap.parsers.string,
    .APP_ID = clap.parsers.string,
    .ACTIVITY = clap.parsers.string,
};

const params = clap.parseParamsComptime(
    \\-h, --help                         Display this help and exit.
    \\    --device <DEVICE>             Select target without prompting.
    \\    --debugger <DEBUGGER>         Override debugger mode.
    \\    --non-interactive             Fail instead of prompting for selection.
    \\    --once                        Launch and exit without attaching.
    \\    --monitor-timeout <SECONDS>   Stop log streaming after N seconds.
    \\    --regenerate-host             Regenerate iOS hosts before running.
    \\    --__wizig-skip-device-discovery  Internal: skip discovery and reuse --device.
    \\    --__wizig-skip-codegen        Internal: skip codegen preflight.
    \\    --scheme <SCHEME>             iOS-only scheme override.
    \\    --bundle-id <BUNDLE_ID>       iOS-only bundle identifier override.
    \\    --module <MODULE>             Android-only Gradle module override.
    \\    --app-id <APP_ID>             Android-only application identifier override.
    \\    --activity <ACTIVITY>         Android-only activity override.
    \\<PLATFORM>                        ios or android.
    \\<PROJECT_DIR>                     Selected platform project directory.
    \\
);

/// Parses CLI arguments into validated platform run options.
pub fn parseRunOptions(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?types.RunOptions {
    var iter = clap_support.SliceIterator.init(args);
    var diag = clap.Diagnostic{};
    var result = clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try clap_support.reportDiagnostic(stderr, diag, err);
        return error.RunFailed;
    };
    defer result.deinit();

    if (result.args.help != 0) return null;
    const platform_raw = result.positionals[0] orelse {
        try stderr.writeAll("error: run expects <ios|android> <project_dir> [options]\n");
        return error.RunFailed;
    };
    const project_dir = result.positionals[1] orelse {
        try stderr.writeAll("error: run expects <ios|android> <project_dir> [options]\n");
        return error.RunFailed;
    };

    var options = types.RunOptions{
        .platform = std.meta.stringToEnum(types.Platform, platform_raw) orelse {
            try stderr.print("error: unknown platform '{s}', expected ios or android\n", .{platform_raw});
            return error.RunFailed;
        },
        .project_dir = project_dir,
        .device_selector = result.args.device,
        .debugger = .auto,
        .non_interactive = @field(result.args, "non-interactive") != 0,
        .once = result.args.once != 0,
        .monitor_timeout_seconds = if (@field(result.args, "monitor-timeout")) |raw|
            try parseMonitorTimeout(raw, stderr)
        else
            null,
        .regenerate_host = @field(result.args, "regenerate-host") != 0,
        .skip_device_discovery = @field(result.args, "__wizig-skip-device-discovery") != 0,
        .skip_codegen = @field(result.args, "__wizig-skip-codegen") != 0,
        .scheme = result.args.scheme,
        .bundle_id = @field(result.args, "bundle-id"),
        .module = result.args.module orelse "app",
        .app_id = @field(result.args, "app-id"),
        .activity = result.args.activity,
    };

    if (result.args.debugger) |raw| {
        options.debugger = std.meta.stringToEnum(types.DebuggerMode, raw) orelse {
            try stderr.print("error: invalid debugger mode '{s}'\n", .{raw});
            return error.RunFailed;
        };
    }

    switch (options.platform) {
        .ios => {
            if (!std.mem.eql(u8, options.module, "app")) {
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

test "parseRunOptions parses shared and platform flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = (try parseRunOptions(std.testing.allocator, &err_writer.writer, &.{
        "android", "examples/android/WizigExample", "--device", "emulator-5554", "--module", "app", "--debugger", "none", "--monitor-timeout", "90", "--once",
    })).?;
    try std.testing.expectEqual(types.Platform.android, options.platform);
    try std.testing.expectEqualStrings("examples/android/WizigExample", options.project_dir);
    try std.testing.expectEqualStrings("emulator-5554", options.device_selector.?);
    try std.testing.expectEqual(types.DebuggerMode.none, options.debugger);
    try std.testing.expectEqual(@as(?u64, 90), options.monitor_timeout_seconds);
    try std.testing.expect(options.once);
    try std.testing.expect(!options.regenerate_host);
    try std.testing.expect(!options.skip_device_discovery);
}

test "parseRunOptions rejects mixed platform flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(
        error.RunFailed,
        parseRunOptions(std.testing.allocator, &err_writer.writer, &.{ "ios", "examples/ios/WizigExample", "--module", "custom-module" }),
    );
}

test "parseRunOptions parses internal skip-codegen flag" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = (try parseRunOptions(std.testing.allocator, &err_writer.writer, &.{
        "android", "examples/android/WizigExample", "--device", "emulator-5554", "--__wizig-skip-codegen",
    })).?;
    try std.testing.expect(options.skip_codegen);
}

test "parseRunOptions parses inline monitor timeout form" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = (try parseRunOptions(std.testing.allocator, &err_writer.writer, &.{
        "ios", "examples/ios/WizigExample", "--monitor-timeout=45",
    })).?;
    try std.testing.expectEqual(@as(?u64, 45), options.monitor_timeout_seconds);
}
