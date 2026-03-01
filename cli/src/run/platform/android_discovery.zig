//! Android device and AVD discovery/selection helpers.
//!
//! This module provides enumeration and selection behavior for connected devices
//! and emulator profiles, including AVD boot and adb visibility waits.
const std = @import("std");
const Io = std.Io;

const process = @import("process_supervisor.zig");
const selection = @import("selection.zig");
const text_utils = @import("text_utils.zig");
const types = @import("types.zig");

/// Discovers connected Android devices via `adb devices -l`.
pub fn discoverAndroidDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.AndroidDevice {
    const result = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "adb", "devices", "-l" },
        .label = "discover Android devices",
    }, .{});

    var devices = try parseAndroidDevicesOutput(arena, result.stdout);
    std.mem.sort(types.AndroidDevice, devices.items, {}, lessAndroidDevice);
    return devices.toOwnedSlice(arena);
}

/// Discovers available Android Virtual Device profile names.
pub fn discoverAndroidAvds(arena: std.mem.Allocator, io: std.Io) ![]const []const u8 {
    const result = process.runCapture(arena, io, .{
        .argv = &.{ "emulator", "-list-avds" },
        .label = "discover Android AVD profiles",
    }, .{}) catch return arena.alloc([]const u8, 0);

    if (!process.termIsSuccess(result.term)) {
        return arena.alloc([]const u8, 0);
    }

    var avds = std.ArrayList([]const u8).empty;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        try avds.append(arena, try arena.dupe(u8, line));
    }
    std.mem.sort([]const u8, avds.items, {}, text_utils.lessStringSlice);
    return avds.toOwnedSlice(arena);
}

/// Resolves Android target from selector or interactive prompt.
pub fn chooseAndroidTarget(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    devices: []const types.AndroidDevice,
    avds: []const []const u8,
    selector_raw: ?[]const u8,
    non_interactive: bool,
) !types.AndroidTarget {
    if (selector_raw) |needle| {
        if (selection.findAndroidDeviceBySelector(devices, needle)) |device| return .{ .device = device };
        if (selection.findAvdBySelector(avds, needle)) |avd_name| return .{ .avd = avd_name };
        try stderr.print("error: Android target '{s}' not found\n", .{needle});
        return error.RunFailed;
    }

    const total = devices.len + avds.len;
    if (total == 1) {
        if (devices.len == 1) return .{ .device = devices[0] };
        return .{ .avd = avds[0] };
    }
    if (non_interactive) {
        try stderr.writeAll("error: multiple Android targets found; pass --device\n");
        return error.RunFailed;
    }

    try stdout.writeAll("available Android targets:\n");
    for (devices, 0..) |device, idx| {
        try stdout.print("  {d}. {s} [{s}]\n", .{ idx + 1, device.model, device.serial });
    }
    for (avds, 0..) |avd_name, idx| {
        try stdout.print("  {d}. AVD {s}\n", .{ devices.len + idx + 1, avd_name });
    }
    try stdout.flush();

    const index = try selection.promptSelection(arena, io, stderr, stdout, total);
    if (index < devices.len) return .{ .device = devices[index] };
    return .{ .avd = avds[index - devices.len] };
}

/// Starts an AVD profile in detached emulator process.
pub fn startAvd(io: std.Io, stderr: *Io.Writer, avd_name: []const u8) !void {
    _ = std.process.spawn(io, .{
        .argv = &.{ "emulator", "-avd", avd_name },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch |err| {
        try stderr.print("error: failed to start emulator '{s}': {s}\n", .{ avd_name, @errorName(err) });
        return error.RunFailed;
    };
}

/// Waits until a newly-started AVD appears in `adb devices`.
pub fn waitForStartedEmulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    existing_devices: []const types.AndroidDevice,
    avd_name: []const u8,
) !types.AndroidDevice {
    var attempt: usize = 0;
    while (attempt < 240) : (attempt += 1) {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        const result = process.runCapture(scratch, io, .{
            .argv = &.{ "adb", "devices", "-l" },
            .label = "wait for started Android emulator",
        }, .{}) catch {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        };
        if (!process.termIsSuccess(result.term)) {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        }

        var devices = try parseAndroidDevicesOutput(scratch, result.stdout);
        for (devices.items) |device| {
            if (!std.mem.startsWith(u8, device.serial, "emulator-")) continue;
            if (containsAndroidSerial(existing_devices, device.serial)) continue;
            return cloneAndroidDevice(arena, device);
        }
        if (existing_devices.len == 0 and devices.items.len == 1 and std.mem.startsWith(u8, devices.items[0].serial, "emulator-")) {
            return cloneAndroidDevice(arena, devices.items[0]);
        }
        std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
    }

    try stderr.print("error: timed out waiting for AVD '{s}' to appear in adb devices\n", .{avd_name});
    return error.RunFailed;
}

fn parseAndroidDevicesOutput(arena: std.mem.Allocator, output: []const u8) !std.ArrayList(types.AndroidDevice) {
    var devices = std.ArrayList(types.AndroidDevice).empty;
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "List of devices attached")) continue;
        if (line[0] == '*') continue;

        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const serial = tokens.next() orelse continue;
        const state = tokens.next() orelse continue;
        if (!std.mem.eql(u8, state, "device")) continue;

        var model_name: ?[]const u8 = null;
        while (tokens.next()) |token| {
            if (std.mem.startsWith(u8, token, "model:")) {
                model_name = token["model:".len..];
            }
        }

        const model = model_name orelse serial;
        try devices.append(arena, .{
            .serial = try arena.dupe(u8, serial),
            .model = try arena.dupe(u8, model),
            .state = try arena.dupe(u8, state),
        });
    }
    return devices;
}

fn containsAndroidSerial(devices: []const types.AndroidDevice, serial: []const u8) bool {
    for (devices) |device| {
        if (std.mem.eql(u8, device.serial, serial)) return true;
    }
    return false;
}

fn cloneAndroidDevice(allocator: std.mem.Allocator, device: types.AndroidDevice) !types.AndroidDevice {
    return .{
        .serial = try allocator.dupe(u8, device.serial),
        .model = try allocator.dupe(u8, device.model),
        .state = try allocator.dupe(u8, device.state),
    };
}

fn lessAndroidDevice(_: void, a: types.AndroidDevice, b: types.AndroidDevice) bool {
    return std.mem.lessThan(u8, a.serial, b.serial);
}
