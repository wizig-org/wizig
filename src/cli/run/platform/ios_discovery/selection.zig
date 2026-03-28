//! iOS discovery selection and filtering helpers.
const std = @import("std");
const Io = std.Io;

const base_selection = @import("../selection.zig");
const types = @import("../types.zig");

/// Filters discovered iOS devices by allowed destination IDs.
pub fn filterIosDevicesBySupportedIds(
    arena: std.mem.Allocator,
    devices: []const types.IosDevice,
    supported_ids: []const []const u8,
) ![]types.IosDevice {
    var filtered = std.ArrayList(types.IosDevice).empty;
    errdefer filtered.deinit(arena);

    for (devices) |device| {
        if (!containsSupportedId(supported_ids, device.udid)) continue;
        try filtered.append(arena, device);
    }

    return filtered.toOwnedSlice(arena);
}

/// Resolves concrete iOS device from selector or interactive prompt.
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
        if (base_selection.findIosDeviceBySelector(devices, needle)) |device| return device;
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

    const index = try base_selection.promptSelection(arena, io, stderr, stdout, devices.len);
    return devices[index];
}

fn containsSupportedId(supported_ids: []const []const u8, udid: []const u8) bool {
    for (supported_ids) |supported_id| {
        if (std.mem.eql(u8, supported_id, udid)) return true;
    }
    return false;
}

test "filterIosDevicesBySupportedIds keeps only matching devices" {
    const devices = [_]types.IosDevice{
        .{ .name = "Sim A", .udid = "A", .runtime = "iOS.18.0", .state = "Booted" },
        .{ .name = "Sim B", .udid = "B", .runtime = "iOS.18.0", .state = "Shutdown" },
    };
    const supported_ids = [_][]const u8{"B"};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const filtered = try filterIosDevicesBySupportedIds(arena.allocator(), &devices, &supported_ids);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("B", filtered[0].udid);
}
