//! Android launch metadata resolution.
//!
//! This module resolves the application id and launch activity from explicit
//! options, manifest metadata, and `aapt` output.
const std = @import("std");
const Io = std.Io;

const android_app_info = @import("../android_app_info.zig");
const config_parse = @import("../config_parse.zig");
const process = @import("../process_supervisor.zig");
const tooling = @import("../tooling.zig");

/// Resolved Android launch metadata used for install and launch commands.
pub const AndroidLaunchMetadata = struct {
    app_id: []const u8,
    activity: []const u8,
};

/// Optional app launch hints.
pub const AndroidLaunchHints = struct {
    app_id: ?[]const u8 = null,
    activity: ?[]const u8 = null,
};

/// Merges a primary hint set with fallback values for missing fields.
pub fn mergeAndroidLaunchHints(primary: AndroidLaunchHints, fallback: AndroidLaunchHints) AndroidLaunchHints {
    return .{
        .app_id = primary.app_id orelse fallback.app_id,
        .activity = primary.activity orelse fallback.activity,
    };
}

/// Resolves the Android application id and activity used to launch the app.
pub fn resolveAndroidLaunchMetadata(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
    apk: []const u8,
    app_id_hint: ?[]const u8,
    activity_hint: ?[]const u8,
) !AndroidLaunchMetadata {
    var hints = AndroidLaunchHints{ .app_id = app_id_hint, .activity = activity_hint };
    if (hints.app_id == null or hints.activity == null) {
        const manifest_info = android_app_info.parseAndroidManifest(arena, io, project_dir, module) catch null;
        if (manifest_info) |info| {
            hints = mergeAndroidLaunchHints(hints, .{ .app_id = info.app_id, .activity = info.activity });
        }
    }

    if ((hints.app_id == null or hints.activity == null) and tooling.commandExists(arena, io, "aapt")) {
        const aapt_result = process.runCapture(
            arena,
            io,
            .{ .argv = &.{ "aapt", "dump", "badging", apk }, .label = "parse Android badging" },
            .{},
        ) catch |err| {
            try stderr.print("error: failed to run aapt to discover Android app id/activity: {s}\n", .{@errorName(err)});
            try stderr.writeAll("hint: pass --app-id and --activity manually\n");
            return error.RunFailed;
        };

        if (process.termIsSuccess(aapt_result.term)) {
            android_app_info.parseAaptBadging(aapt_result.stdout, &hints.app_id, &hints.activity);
        }
    }

    const app_id = hints.app_id orelse {
        try stderr.writeAll("error: unable to determine Android application id (use --app-id)\n");
        return error.RunFailed;
    };
    const activity = hints.activity orelse {
        try stderr.writeAll("error: unable to determine launch activity (use --activity)\n");
        return error.RunFailed;
    };
    return .{ .app_id = app_id, .activity = activity };
}

test "mergeAndroidLaunchHints fills missing values from fallback" {
    const merged = mergeAndroidLaunchHints(
        .{ .app_id = null, .activity = "MainActivity" },
        .{ .app_id = "com.example.app", .activity = null },
    );

    try std.testing.expectEqualStrings("com.example.app", merged.app_id.?);
    try std.testing.expectEqualStrings("MainActivity", merged.activity.?);
}

test "mergeAndroidLaunchHints keeps explicit values" {
    const merged = mergeAndroidLaunchHints(
        .{ .app_id = "com.example.app", .activity = "MainActivity" },
        .{ .app_id = "com.other.app", .activity = "OtherActivity" },
    );

    try std.testing.expectEqualStrings("com.example.app", merged.app_id.?);
    try std.testing.expectEqualStrings("MainActivity", merged.activity.?);
}
