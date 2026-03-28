//! Android APK and manifest metadata resolution helpers.
//!
//! This module locates built debug APK artifacts and extracts application id /
//! launch activity details from manifest, Gradle DSL, or `aapt` output.
const std = @import("std");
const Io = std.Io;

const config_parse = @import("config_parse.zig");
const fs_utils = @import("fs_utils.zig");
const process = @import("process_supervisor.zig");
const text_utils = @import("text_utils.zig");

/// Parsed Android manifest metadata used for launch target resolution.
pub const AndroidManifestInfo = struct {
    app_id: ?[]const u8 = null,
    activity: ?[]const u8 = null,
};

/// Finds a debug APK from standard Gradle outputs/intermediates directories.
pub fn findDebugApk(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
) ![]const u8 {
    const apk_outputs_root = try std.fmt.allocPrint(
        arena,
        "{s}{s}{s}{s}build{s}outputs{s}apk",
        .{ project_dir, std.fs.path.sep_str, module, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );
    const apk_intermediates_root = try std.fmt.allocPrint(
        arena,
        "{s}{s}{s}{s}build{s}intermediates{s}apk",
        .{ project_dir, std.fs.path.sep_str, module, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );

    var first: ?[]const u8 = null;
    var preferred: ?[]const u8 = null;

    const roots = [_][]const u8{ apk_outputs_root, apk_intermediates_root };
    for (roots) |root| {
        if (!fs_utils.pathExists(io, root)) continue;

        const result = try process.runCaptureChecked(arena, io, stderr, .{
            .argv = &.{ "find", root, "-type", "f", "-name", "*-debug.apk" },
            .label = "locate Android debug APK",
        }, .{});

        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0) continue;
            if (first == null) first = line;
            if (std.mem.endsWith(u8, line, "/app-debug.apk") or std.mem.endsWith(u8, line, "\\app-debug.apk")) {
                preferred = line;
                break;
            }
        }
        if (preferred != null) break;
    }

    const selected = preferred orelse first orelse {
        try stderr.writeAll("error: could not find a debug APK after build\n");
        return error.RunFailed;
    };
    return arena.dupe(u8, selected);
}

/// Parses manifest and module Gradle files to infer app id/activity.
pub fn parseAndroidManifest(
    arena: std.mem.Allocator,
    io: std.Io,
    project_dir: []const u8,
    module: []const u8,
) !AndroidManifestInfo {
    const manifest_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}{s}{s}src{s}main{s}AndroidManifest.xml",
        .{ project_dir, std.fs.path.sep_str, module, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );
    const content = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, arena, .limited(512 * 1024)) catch return error.RunFailed;

    var info = AndroidManifestInfo{};
    info.app_id = config_parse.extractXmlAttribute(content, "manifest", "package");
    info.activity = config_parse.extractXmlAttribute(content, "activity", "android:name");

    if (info.app_id == null) {
        const build_gradle_path = try std.fmt.allocPrint(
            arena,
            "{s}{s}{s}{s}build.gradle.kts",
            .{ project_dir, std.fs.path.sep_str, module, std.fs.path.sep_str },
        );
        const gradle_content = std.Io.Dir.cwd().readFileAlloc(io, build_gradle_path, arena, .limited(512 * 1024)) catch null;
        if (gradle_content) |build_contents| {
            info.app_id = config_parse.extractGradleStringValue(build_contents, "applicationId") orelse
                config_parse.extractGradleStringValue(build_contents, "namespace");
        }
    }
    return info;
}

/// Parses `aapt dump badging` output into app id/activity fields.
pub fn parseAaptBadging(output: []const u8, app_id: *?[]const u8, activity: *?[]const u8) void {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (app_id.* == null and std.mem.startsWith(u8, line, "package:")) {
            app_id.* = text_utils.extractAfterMarker(line, "name='");
        }
        if (activity.* == null and std.mem.startsWith(u8, line, "launchable-activity:")) {
            activity.* = text_utils.extractAfterMarker(line, "name='");
        }
    }
}
