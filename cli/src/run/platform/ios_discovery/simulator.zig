//! iOS simulator discovery and JSON parsing helpers.
const std = @import("std");
const Io = std.Io;

const json = @import("json.zig");
const process = @import("../process_supervisor.zig");
const types = @import("../types.zig");

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

    return parseSimulatorDevices(arena, devices_value.object);
}

/// Parses the `simctl` devices object into sorted iOS simulator models.
pub fn parseSimulatorDevices(
    arena: std.mem.Allocator,
    devices_object: std.json.ObjectMap,
) ![]types.IosDevice {
    var devices = std.ArrayList(types.IosDevice).empty;
    errdefer devices.deinit(arena);

    var runtime_it = devices_object.iterator();
    while (runtime_it.next()) |runtime_entry| {
        const runtime_key = runtime_entry.key_ptr.*;
        if (std.mem.indexOf(u8, runtime_key, "iOS-") == null) continue;

        const runtime_value = runtime_entry.value_ptr.*;
        if (runtime_value != .array) continue;

        const runtime_label = try runtimeLabelFromKey(arena, runtime_key);
        for (runtime_value.array.items) |device_value| {
            if (device_value != .object) continue;

            const name = json.objectString(device_value.object, "name") orelse continue;
            const udid = json.objectString(device_value.object, "udid") orelse continue;
            const state = json.objectString(device_value.object, "state") orelse "Unknown";
            const available = json.objectBool(device_value.object, "isAvailable") orelse true;
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

fn lessIosDevice(_: void, a: types.IosDevice, b: types.IosDevice) bool {
    const a_booted = std.mem.eql(u8, a.state, "Booted");
    const b_booted = std.mem.eql(u8, b.state, "Booted");
    if (a_booted != b_booted) return a_booted;

    if (!std.mem.eql(u8, a.runtime, b.runtime)) {
        return std.mem.lessThan(u8, a.runtime, b.runtime);
    }
    return std.mem.lessThan(u8, a.name, b.name);
}

test "parseSimulatorDevices filters and sorts simulator results" {
    const input =
        \\{
        \\  "devices": {
        \\    "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
        \\      { "name": "Zeta", "udid": "z", "state": "Shutdown", "isAvailable": true },
        \\      { "name": "Alpha", "udid": "a", "state": "Booted", "isAvailable": true },
        \\      { "name": "Hidden", "udid": "h", "state": "Booted", "isAvailable": false }
        \\    ],
        \\    "com.apple.CoreSimulator.SimRuntime.watchOS-11-0": [
        \\      { "name": "Ignored", "udid": "w", "state": "Shutdown", "isAvailable": true }
        \\    ]
        \\  }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const root = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), input, .{});
    const devices_value = root.object.get("devices").?;
    const devices = try parseSimulatorDevices(arena.allocator(), devices_value.object);

    try std.testing.expectEqual(@as(usize, 2), devices.len);
    try std.testing.expectEqualStrings("Alpha", devices[0].name);
    try std.testing.expectEqualStrings("Booted", devices[0].state);
    try std.testing.expectEqualStrings("iOS.18.0", devices[0].runtime);
    try std.testing.expectEqualStrings("Zeta", devices[1].name);
    try std.testing.expectEqualStrings("Shutdown", devices[1].state);
}

test "runtimeLabelFromKey normalizes simctl runtime identifiers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const label = try runtimeLabelFromKey(arena.allocator(), "com.apple.CoreSimulator.SimRuntime.iOS-17-4");
    try std.testing.expectEqualStrings("iOS.17.4", label);
}
