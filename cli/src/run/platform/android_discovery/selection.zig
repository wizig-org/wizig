//! Android target selection helpers.
const std = @import("std");
const Io = std.Io;

const chooser = @import("../selection.zig");
const types = @import("../types.zig");

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
        if (resolveTargetBySelector(devices, avds, needle)) |target| return target;
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

    const index = try chooser.promptSelection(arena, io, stderr, stdout, total);
    if (index < devices.len) return .{ .device = devices[index] };
    return .{ .avd = avds[index - devices.len] };
}

/// Resolves a selector string to either a device or an AVD.
pub fn resolveTargetBySelector(
    devices: []const types.AndroidDevice,
    avds: []const []const u8,
    selector: []const u8,
) ?types.AndroidTarget {
    if (chooser.findAndroidDeviceBySelector(devices, selector)) |device| {
        return .{ .device = device };
    }
    if (chooser.findAvdBySelector(avds, selector)) |avd_name| {
        return .{ .avd = avd_name };
    }
    return null;
}

test "resolveTargetBySelector finds device and avd selectors" {
    const devices = [_]types.AndroidDevice{
        .{ .serial = "emulator-5554", .model = "Pixel", .state = "device" },
    };
    const avds = [_][]const u8{"Pixel_8"};

    const device_target = resolveTargetBySelector(&devices, &avds, "emulator-5554") orelse return error.TestUnexpectedResult;
    switch (device_target) {
        .device => |device| try std.testing.expectEqualStrings("emulator-5554", device.serial),
        else => return error.TestUnexpectedResult,
    }

    const avd_target = resolveTargetBySelector(&devices, &avds, "avd:Pixel_8") orelse return error.TestUnexpectedResult;
    switch (avd_target) {
        .avd => |avd_name| try std.testing.expectEqualStrings("Pixel_8", avd_name),
        else => return error.TestUnexpectedResult,
    }
}

test "resolveTargetBySelector returns null for unknown selector" {
    const devices = [_]types.AndroidDevice{};
    const avds = [_][]const u8{};
    try std.testing.expect(resolveTargetBySelector(&devices, &avds, "missing") == null);
}
