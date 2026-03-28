//! Interactive and selector-based target resolution utilities.
//!
//! The run command supports both explicit selectors and guided prompts.
//! This module encapsulates that UX logic for iOS and Android targets.
const std = @import("std");
const Io = std.Io;

const types = @import("types.zig");

/// Prompts the user for a numeric selection index in the allowed range.
pub fn promptSelection(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    option_count: usize,
) !usize {
    var attempts: usize = 0;
    while (attempts < 8) : (attempts += 1) {
        try stdout.print("select target [1-{d}]: ", .{option_count});
        try stdout.flush();

        const line = readTrimmedLine(arena, io) catch |err| switch (err) {
            error.EndOfStream => {
                try stderr.writeAll("error: no input received\n");
                return error.RunFailed;
            },
            else => |e| return e,
        };
        const parsed = std.fmt.parseInt(usize, line, 10) catch {
            try stderr.print("error: invalid selection '{s}'\n", .{line});
            try stderr.flush();
            continue;
        };
        if (parsed >= 1 and parsed <= option_count) {
            return parsed - 1;
        }
        try stderr.print("error: selection must be between 1 and {d}\n", .{option_count});
        try stderr.flush();
    }

    return error.RunFailed;
}

/// Reads one input line from stdin and trims surrounding whitespace.
pub fn readTrimmedLine(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    var stdin_buffer: [256]u8 = undefined;
    var file_reader = std.Io.File.stdin().reader(io, &stdin_buffer);

    const raw_line = file_reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => blk: {
            if (file_reader.interface.bufferedLen() == 0) return error.EndOfStream;
            break :blk file_reader.interface.buffered();
        },
        else => |e| return e,
    };

    const trimmed = std.mem.trim(u8, raw_line, " \t\r");
    return arena.dupe(u8, trimmed);
}

/// Finds an iOS device by exact UDID or case-insensitive display name.
pub fn findIosDeviceBySelector(
    devices: []const types.IosDevice,
    selector: []const u8,
) ?types.IosDevice {
    for (devices) |device| {
        if (std.mem.eql(u8, device.udid, selector)) return device;
        if (std.ascii.eqlIgnoreCase(device.name, selector)) return device;
    }
    return null;
}

/// Finds an Android device by exact serial or case-insensitive model name.
pub fn findAndroidDeviceBySelector(
    devices: []const types.AndroidDevice,
    selector: []const u8,
) ?types.AndroidDevice {
    for (devices) |device| {
        if (std.mem.eql(u8, device.serial, selector)) return device;
        if (std.ascii.eqlIgnoreCase(device.model, selector)) return device;
    }
    return null;
}

/// Finds an AVD profile by normalized selector (`avd:<name>` supported).
pub fn findAvdBySelector(avds: []const []const u8, selector: []const u8) ?[]const u8 {
    const normalized = if (std.mem.startsWith(u8, selector, "avd:")) selector["avd:".len..] else selector;
    for (avds) |avd_name| {
        if (std.mem.eql(u8, avd_name, normalized)) return avd_name;
        if (std.ascii.eqlIgnoreCase(avd_name, normalized)) return avd_name;
    }
    return null;
}
