//! iOS simulator and physical device discovery and selection utilities.
//!
//! This module handles simulator enumeration, physical device discovery,
//! scheme destination filtering, selector matching, and interactive target
//! selection for iOS runs.
const std = @import("std");
const Io = std.Io;

const process = @import("process_supervisor.zig");
const selection = @import("selection.zig");
const text_utils = @import("text_utils.zig");
const types = @import("types.zig");

/// Lists available iOS simulators from `simctl`.
pub fn discoverIosDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.IosDevice {
    const result = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcrun", "simctl", "list", "devices", "available", "--json" },
        .label = "discover iOS simulators",
    }, .{});

    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, result.stdout, .{}) catch |err| {
        try stderr.print("error: failed to parse simctl JSON output: {s}\n", .{@errorName(err)});
        return error.RunFailed;
    };
    if (root != .object) {
        try stderr.writeAll("error: unexpected simctl JSON payload\n");
        return error.RunFailed;
    }
    const devices_value = root.object.get("devices") orelse {
        try stderr.writeAll("error: simctl JSON payload missing devices object\n");
        return error.RunFailed;
    };
    if (devices_value != .object) {
        try stderr.writeAll("error: simctl devices payload is not an object\n");
        return error.RunFailed;
    }

    var devices = std.ArrayList(types.IosDevice).empty;
    var runtime_it = devices_value.object.iterator();
    while (runtime_it.next()) |runtime_entry| {
        const runtime_key = runtime_entry.key_ptr.*;
        if (std.mem.indexOf(u8, runtime_key, "iOS-") == null) continue;

        const runtime_value = runtime_entry.value_ptr.*;
        if (runtime_value != .array) continue;

        const runtime_label = try runtimeLabelFromKey(arena, runtime_key);
        for (runtime_value.array.items) |device_value| {
            if (device_value != .object) continue;

            const name = jsonObjectString(device_value.object, "name") orelse continue;
            const udid = jsonObjectString(device_value.object, "udid") orelse continue;
            const state = jsonObjectString(device_value.object, "state") orelse "Unknown";
            const available = jsonObjectBool(device_value.object, "isAvailable") orelse true;
            if (!available) continue;

            try devices.append(arena, .{
                .name = try arena.dupe(u8, name),
                .udid = try arena.dupe(u8, udid),
                .runtime = runtime_label,
                .state = try arena.dupe(u8, state),
            });
        }
    }

    std.mem.sort(types.IosDevice, devices.items, {}, lessIosDevice);
    return devices.toOwnedSlice(arena);
}

/// Returns iOS simulator IDs supported by the given Xcode scheme.
pub fn discoverIosSupportedDestinationIds(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    xcode_project: []const u8,
    scheme: []const u8,
) ![]const []const u8 {
    const result = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcodebuild", "-project", xcode_project, "-scheme", scheme, "-showdestinations" },
        .cwd_path = project_dir,
        .label = "discover supported iOS destinations",
    }, .{});

    var ids = std.ArrayList([]const u8).empty;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (std.mem.indexOf(u8, line, "platform:iOS Simulator") == null) continue;
        const id = text_utils.extractInlineField(line, "id:") orelse continue;
        if (std.mem.startsWith(u8, id, "dvtdevice-")) continue;
        try ids.append(arena, try arena.dupe(u8, id));
    }
    return ids.toOwnedSlice(arena);
}

/// Lists connected physical iOS devices via `xcrun devicectl`.
pub fn discoverIosPhysicalDevices(arena: std.mem.Allocator, io: std.Io) ![]types.IosDevice {
    // devicectl is available on macOS 14+ (Xcode 15+).  Fall back gracefully
    // when the tool is missing so that older hosts still work for simulators.
    const result = process.runCapture(arena, io, .{
        .argv = &.{ "xcrun", "devicectl", "list", "devices", "--json-output", "/dev/stdout" },
        .label = "discover iOS physical devices",
    }, .{}) catch return &[_]types.IosDevice{};

    if (!process.termIsSuccess(result.term)) return &[_]types.IosDevice{};

    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, result.stdout, .{}) catch return &[_]types.IosDevice{};
    if (root != .object) return &[_]types.IosDevice{};

    // devicectl nests devices under result.devices[]
    const result_obj = root.object.get("result") orelse return &[_]types.IosDevice{};
    if (result_obj != .object) return &[_]types.IosDevice{};
    const devices_value = result_obj.object.get("devices") orelse return &[_]types.IosDevice{};
    if (devices_value != .array) return &[_]types.IosDevice{};

    var devices = std.ArrayList(types.IosDevice).empty;
    for (devices_value.array.items) |device_value| {
        if (device_value != .object) continue;

        const identifier = jsonObjectString(device_value.object, "identifier") orelse continue;

        // Device name lives in deviceProperties.name
        const props = device_value.object.get("deviceProperties") orelse continue;
        if (props != .object) continue;
        const name = jsonObjectString(props.object, "name") orelse continue;
        const os_version_str = blk: {
            if (props.object.get("osVersionNumber")) |v| {
                if (v == .string) break :blk v.string;
            }
            break :blk "iOS";
        };

        // Connection state lives in connectionProperties.transportType
        const conn = device_value.object.get("connectionProperties") orelse continue;
        if (conn != .object) continue;
        const transport = jsonObjectString(conn.object, "transportType") orelse "unknown";
        _ = transport;

        const state_str: []const u8 = if (device_value.object.get("visibilityClass")) |v| blk: {
            if (v == .string) break :blk v.string;
            break :blk "connected";
        } else "connected";
        _ = state_str;

        try devices.append(arena, .{
            .name = try arena.dupe(u8, name),
            .udid = try arena.dupe(u8, identifier),
            .runtime = try std.fmt.allocPrint(arena, "iOS.{s}", .{os_version_str}),
            .state = try arena.dupe(u8, "Connected"),
            .kind = .device,
        });
    }

    return devices.toOwnedSlice(arena);
}

/// Filters discovered iOS devices by allowed destination IDs.
pub fn filterIosDevicesBySupportedIds(
    arena: std.mem.Allocator,
    devices: []const types.IosDevice,
    supported_ids: []const []const u8,
) ![]types.IosDevice {
    var filtered = std.ArrayList(types.IosDevice).empty;
    for (devices) |device| {
        if (!text_utils.containsString(supported_ids, device.udid)) continue;
        try filtered.append(arena, device);
    }
    return filtered.toOwnedSlice(arena);
}

/// Resolves concrete iOS device from selector/prompt.
pub fn chooseIosDevice(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    devices: []const types.IosDevice,
    selector: ?[]const u8,
    non_interactive: bool,
) !types.IosDevice {
    if (selector) |needle| {
        if (selection.findIosDeviceBySelector(devices, needle)) |device| return device;
        try stderr.print("error: iOS target '{s}' not found\n", .{needle});
        return error.RunFailed;
    }

    if (devices.len == 1) return devices[0];
    if (non_interactive) {
        try stderr.writeAll("error: multiple iOS targets found; pass --device\n");
        return error.RunFailed;
    }

    try stdout.writeAll("available iOS targets:\n");
    for (devices, 0..) |device, idx| {
        const kind_label: []const u8 = switch (device.kind) {
            .simulator => "sim",
            .device => "dev",
        };
        try stdout.print("  {d}. [{s}] {s} [{s}] ({s}, {s})\n", .{ idx + 1, kind_label, device.name, device.udid, device.runtime, device.state });
    }
    try stdout.flush();

    const index = try selection.promptSelection(arena, io, stderr, stdout, devices.len);
    return devices[index];
}

fn runtimeLabelFromKey(arena: std.mem.Allocator, runtime_key: []const u8) ![]const u8 {
    const marker = "SimRuntime.";
    const start = std.mem.indexOf(u8, runtime_key, marker) orelse return arena.dupe(u8, runtime_key);
    const suffix = runtime_key[start + marker.len ..];
    const out = try arena.dupe(u8, suffix);
    for (out) |*char| {
        if (char.* == '-') char.* = '.';
    }
    return out;
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

fn lessIosDevice(_: void, a: types.IosDevice, b: types.IosDevice) bool {
    const a_booted = std.mem.eql(u8, a.state, "Booted");
    const b_booted = std.mem.eql(u8, b.state, "Booted");
    if (a_booted != b_booted) return a_booted;

    if (!std.mem.eql(u8, a.runtime, b.runtime)) {
        return std.mem.lessThan(u8, a.runtime, b.runtime);
    }
    return std.mem.lessThan(u8, a.name, b.name);
}
