//! Host and device discovery for unified run mode.
//!
//! Unified run needs lightweight, platform-agnostic discovery to choose a
//! concrete target before delegating into platform-specific execution.
const std = @import("std");
const Io = std.Io;

const fs_utils = @import("../platform/fs_utils.zig");
const process = @import("../platform/process_supervisor.zig");
const selection = @import("../platform/selection.zig");
const types = @import("types.zig");

/// Returns true when the project has an iOS host with at least one `.xcodeproj`.
pub fn hasIosHost(arena: std.mem.Allocator, io: std.Io, ios_dir: []const u8) bool {
    if (!fs_utils.pathExists(io, ios_dir)) return false;

    const result = process.runCapture(arena, io, .{
        .argv = &.{ "find", ios_dir, "-maxdepth", "1", "-type", "d", "-name", "*.xcodeproj" },
        .label = "discover iOS host",
    }, .{}) catch return false;
    if (!process.termIsSuccess(result.term)) return false;

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len > 0) return true;
    }
    return false;
}

/// Returns true when the project has Android host Gradle module files.
pub fn hasAndroidHost(io: std.Io, android_dir: []const u8) bool {
    if (!fs_utils.pathExists(io, android_dir)) return false;

    const app_build_kts = std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}app{s}build.gradle.kts", .{ android_dir, std.fs.path.sep_str, std.fs.path.sep_str }) catch return false;
    defer std.heap.page_allocator.free(app_build_kts);
    if (fs_utils.pathExists(io, app_build_kts)) return true;

    const app_build = std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}app{s}build.gradle", .{ android_dir, std.fs.path.sep_str, std.fs.path.sep_str }) catch return false;
    defer std.heap.page_allocator.free(app_build);
    return fs_utils.pathExists(io, app_build);
}

/// Discovers booted/available iOS simulators and excludes `Shutdown` state.
pub fn discoverIosDevicesNonShutdown(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
) ![]types.DeviceInfo {
    const result = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcrun", "simctl", "list", "devices", "available", "--json" },
        .label = "discover iOS simulators",
    }, .{});

    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, result.stdout, .{}) catch |err| {
        try stderr.print("error: failed to parse simctl JSON output: {s}\n", .{@errorName(err)});
        return error.RunFailed;
    };
    if (root != .object) return error.RunFailed;
    const devices_value = root.object.get("devices") orelse return error.RunFailed;
    if (devices_value != .object) return error.RunFailed;

    var devices = std.ArrayList(types.DeviceInfo).empty;
    var runtime_it = devices_value.object.iterator();
    while (runtime_it.next()) |runtime_entry| {
        const runtime_key = runtime_entry.key_ptr.*;
        if (std.mem.indexOf(u8, runtime_key, "iOS-") == null) continue;

        const runtime_value = runtime_entry.value_ptr.*;
        if (runtime_value != .array) continue;

        for (runtime_value.array.items) |device_value| {
            if (device_value != .object) continue;
            const name = jsonObjectString(device_value.object, "name") orelse continue;
            const udid = jsonObjectString(device_value.object, "udid") orelse continue;
            const state = jsonObjectString(device_value.object, "state") orelse "Unknown";
            const available = jsonObjectBool(device_value.object, "isAvailable") orelse true;
            if (!available or std.mem.eql(u8, state, "Shutdown")) continue;

            try devices.append(arena, .{
                .id = try arena.dupe(u8, udid),
                .name = try arena.dupe(u8, name),
                .state = try arena.dupe(u8, state),
            });
        }
    }

    std.mem.sort(types.DeviceInfo, devices.items, {}, types.lessDeviceInfo);
    return devices.toOwnedSlice(arena);
}

/// Discovers connected Android devices from adb output.
pub fn discoverAndroidDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.DeviceInfo {
    const result = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "adb", "devices", "-l" },
        .label = "discover Android devices",
    }, .{});

    var devices = std.ArrayList(types.DeviceInfo).empty;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "List of devices attached") or line[0] == '*') continue;

        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const serial = tokens.next() orelse continue;
        const state = tokens.next() orelse continue;
        if (!std.mem.eql(u8, state, "device")) continue;

        var model_name: ?[]const u8 = null;
        while (tokens.next()) |token| {
            if (std.mem.startsWith(u8, token, "model:")) model_name = token["model:".len..];
        }

        const name = model_name orelse serial;
        try devices.append(arena, .{
            .id = try arena.dupe(u8, serial),
            .name = try arena.dupe(u8, name),
            .state = try arena.dupe(u8, state),
        });
    }

    std.mem.sort(types.DeviceInfo, devices.items, {}, types.lessDeviceInfo);
    return devices.toOwnedSlice(arena);
}

/// Resolves target candidate by selector or interactive prompt.
pub fn chooseCandidate(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    candidates: []const types.Candidate,
    selector: ?[]const u8,
    non_interactive: bool,
) !types.Candidate {
    if (selector) |needle| {
        if (findCandidateBySelector(candidates, needle)) |found| return found;
        try stderr.print("error: target '{s}' not found in available devices\n", .{needle});
        return error.RunFailed;
    }

    if (candidates.len == 1) return candidates[0];
    if (non_interactive) {
        try stderr.writeAll("error: multiple targets found; pass --device\n");
        return error.RunFailed;
    }

    try stdout.writeAll("available run targets:\n");
    for (candidates, 0..) |candidate, idx| {
        try stdout.print("  {d}. [{s}] {s} [{s}] ({s})\n", .{ idx + 1, types.platformLabel(candidate.platform), candidate.name, candidate.id, candidate.state });
    }
    try stdout.flush();

    const index = try selection.promptSelection(arena, io, stderr, stdout, candidates.len);
    return candidates[index];
}

fn findCandidateBySelector(candidates: []const types.Candidate, selector: []const u8) ?types.Candidate {
    var platform_filter: ?types.Platform = null;
    var raw_selector = selector;
    if (std.mem.indexOfScalar(u8, selector, ':')) |separator| {
        const prefix = selector[0..separator];
        const suffix = selector[separator + 1 ..];
        if (std.ascii.eqlIgnoreCase(prefix, "ios")) {
            platform_filter = .ios;
            raw_selector = suffix;
        } else if (std.ascii.eqlIgnoreCase(prefix, "android")) {
            platform_filter = .android;
            raw_selector = suffix;
        }
    }

    for (candidates) |candidate| {
        if (platform_filter) |filtered_platform| {
            if (candidate.platform != filtered_platform) continue;
        }
        if (std.mem.eql(u8, candidate.id, raw_selector)) return candidate;
        if (std.ascii.eqlIgnoreCase(candidate.name, raw_selector)) return candidate;
    }
    return null;
}

fn jsonObjectString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn jsonObjectBool(object: std.json.ObjectMap, key: []const u8) ?bool {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .bool => |v| v,
        else => null,
    };
}
