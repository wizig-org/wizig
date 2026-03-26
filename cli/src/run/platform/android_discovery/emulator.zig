//! Android emulator start and wait helpers.
const std = @import("std");
const Io = std.Io;

const discovery = @import("discovery.zig");
const process = @import("../process_supervisor.zig");
const types = @import("../types.zig");

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

        var devices = try discovery.parseAndroidDevicesOutput(scratch, result.stdout);
        if (try selectNewEmulatorDevice(arena, existing_devices, devices.items)) |device| {
            return device;
        }
        std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
    }

    try stderr.print("error: timed out waiting for AVD '{s}' to appear in adb devices\n", .{avd_name});
    return error.RunFailed;
}

/// Picks the first newly discovered emulator device that is not already known.
pub fn selectNewEmulatorDevice(
    allocator: std.mem.Allocator,
    existing_devices: []const types.AndroidDevice,
    discovered_devices: []const types.AndroidDevice,
) !?types.AndroidDevice {
    for (discovered_devices) |device| {
        if (!isEmulatorSerial(device.serial)) continue;
        if (containsAndroidSerial(existing_devices, device.serial)) continue;
        return try cloneAndroidDevice(allocator, device);
    }

    if (existing_devices.len == 0 and discovered_devices.len == 1 and isEmulatorSerial(discovered_devices[0].serial)) {
        return try cloneAndroidDevice(allocator, discovered_devices[0]);
    }

    return null;
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

fn isEmulatorSerial(serial: []const u8) bool {
    return std.mem.startsWith(u8, serial, "emulator-");
}

test "selectNewEmulatorDevice skips known devices and returns new emulator" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const existing = [_]types.AndroidDevice{
        .{ .serial = "device-123", .model = "Phone", .state = "device" },
    };
    const discovered = [_]types.AndroidDevice{
        .{ .serial = "device-123", .model = "Phone", .state = "device" },
        .{ .serial = "emulator-5554", .model = "Pixel", .state = "device" },
    };

    const selected = try selectNewEmulatorDevice(arena, &existing, &discovered) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("emulator-5554", selected.serial);
    try std.testing.expectEqualStrings("Pixel", selected.model);
}

test "selectNewEmulatorDevice accepts single fresh emulator" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const discovered = [_]types.AndroidDevice{
        .{ .serial = "emulator-5556", .model = "Pixel", .state = "device" },
    };
    const selected = try selectNewEmulatorDevice(arena, &.{}, &discovered) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("emulator-5556", selected.serial);
}
