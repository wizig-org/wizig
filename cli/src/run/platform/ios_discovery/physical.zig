//! iOS physical device discovery and JSON parsing helpers.
const std = @import("std");

const json = @import("json.zig");
const process = @import("../process_supervisor.zig");
const types = @import("../types.zig");

/// Lists connected physical iOS devices via `xcrun devicectl`.
pub fn discoverIosPhysicalDevices(arena: std.mem.Allocator, io: std.Io) ![]types.IosDevice {
    // devicectl is available on macOS 14+ (Xcode 15+). Fall back gracefully
    // when the tool is missing so simulators still work on older hosts.
    const result = process.runCapture(arena, io, .{
        .argv = &.{ "xcrun", "devicectl", "list", "devices", "--json-output", "/dev/stdout" },
        .label = "discover iOS physical devices",
    }, .{}) catch return &[_]types.IosDevice{};

    if (!process.termIsSuccess(result.term)) return &[_]types.IosDevice{};

    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, result.stdout, .{}) catch return &[_]types.IosDevice{};
    return parsePhysicalDevices(arena, root) catch &[_]types.IosDevice{};
}

/// Parses `devicectl` output into physical iOS device models.
pub fn parsePhysicalDevices(
    arena: std.mem.Allocator,
    root: std.json.Value,
) ![]types.IosDevice {
    if (root != .object) return &[_]types.IosDevice{};

    const result_obj = root.object.get("result") orelse return &[_]types.IosDevice{};
    if (result_obj != .object) return &[_]types.IosDevice{};

    const devices_value = result_obj.object.get("devices") orelse return &[_]types.IosDevice{};
    if (devices_value != .array) return &[_]types.IosDevice{};

    var devices = std.ArrayList(types.IosDevice).empty;
    errdefer devices.deinit(arena);

    for (devices_value.array.items) |device_value| {
        if (device_value != .object) continue;

        const identifier = json.objectString(device_value.object, "identifier") orelse continue;
        const props = device_value.object.get("deviceProperties") orelse continue;
        if (props != .object) continue;

        const name = json.objectString(props.object, "name") orelse continue;
        const os_version_str = if (props.object.get("osVersionNumber")) |v|
            if (v == .string) v.string else "iOS"
        else
            "iOS";

        const conn = device_value.object.get("connectionProperties") orelse continue;
        if (conn != .object) continue;
        // Keep the legacy shape gate: devices without connection metadata are ignored.
        _ = json.objectString(conn.object, "transportType") orelse "unknown";
        const visibility_class = if (device_value.object.get("visibilityClass")) |v|
            if (v == .string) v.string else "connected"
        else
            "connected";
        _ = visibility_class;

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

test "parsePhysicalDevices extracts connected devices from devicectl output" {
    const input =
        \\{
        \\  "result": {
        \\    "devices": [
        \\      {
        \\        "identifier": "00000000-0000-0000-0000-0000000000AA",
        \\        "deviceProperties": { "name": "Arata iPhone", "osVersionNumber": "18.2" },
        \\        "connectionProperties": { "transportType": "usb" },
        \\        "visibilityClass": "connected"
        \\      },
        \\      {
        \\        "identifier": "ignored",
        \\        "deviceProperties": { "name": "Missing Connection" }
        \\      }
        \\    ]
        \\  }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const root = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), input, .{});
    const devices = try parsePhysicalDevices(arena.allocator(), root);
    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("Arata iPhone", devices[0].name);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-0000000000AA", devices[0].udid);
    try std.testing.expectEqualStrings("iOS.18.2", devices[0].runtime);
    try std.testing.expectEqualStrings("Connected", devices[0].state);
    try std.testing.expectEqual(types.IosDeviceKind.device, devices[0].kind);
}
