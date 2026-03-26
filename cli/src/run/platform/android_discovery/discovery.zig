//! Android adb and AVD discovery helpers.
const std = @import("std");
const Io = std.Io;

const process = @import("../process_supervisor.zig");
const text_utils = @import("../text_utils.zig");
const types = @import("../types.zig");

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

    return parseAvdListFromOutput(arena, result.stdout);
}

/// Parses `adb devices -l` output into structured device records.
pub fn parseAndroidDevicesOutput(arena: std.mem.Allocator, output: []const u8) !std.ArrayList(types.AndroidDevice) {
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

/// Parses `emulator -list-avds` output into a sorted list of names.
pub fn parseAvdListFromOutput(arena: std.mem.Allocator, output: []const u8) ![]const []const u8 {
    var avds = std.ArrayList([]const u8).empty;
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        try avds.append(arena, try arena.dupe(u8, line));
    }
    std.mem.sort([]const u8, avds.items, {}, text_utils.lessStringSlice);
    return avds.toOwnedSlice(arena);
}

fn lessAndroidDevice(_: void, a: types.AndroidDevice, b: types.AndroidDevice) bool {
    return std.mem.lessThan(u8, a.serial, b.serial);
}

test "parseAndroidDevicesOutput parses and sorts connected devices" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const output =
        \\List of devices attached
        \\emulator-5556 device model:Pixel_8 product:emu transport_id:1
        \\* daemon started successfully
        \\device-123 device
    ;

    const devices = try parseAndroidDevicesOutput(arena, output);
    try std.testing.expectEqual(@as(usize, 2), devices.items.len);
    try std.testing.expectEqualStrings("emulator-5556", devices.items[0].serial);
    try std.testing.expectEqualStrings("Pixel_8", devices.items[0].model);
    try std.testing.expectEqualStrings("device-123", devices.items[1].serial);
    try std.testing.expectEqualStrings("device-123", devices.items[1].model);
}

test "parseAvdListFromOutput trims and sorts avd names" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const avds = try parseAvdListFromOutput(arena, " Pixel 8 \n\nPixel 7\n  Pixel Fold  \n");
    try std.testing.expectEqual(@as(usize, 3), avds.len);
    try std.testing.expectEqualStrings("Pixel 7", avds[0]);
    try std.testing.expectEqualStrings("Pixel 8", avds[1]);
    try std.testing.expectEqualStrings("Pixel Fold", avds[2]);
}
