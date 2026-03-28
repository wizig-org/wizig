//! Android device and AVD discovery/selection facade.
//!
//! This module preserves the public API used by the Android run flow while
//! delegating parsing, selection, and emulator waiting to smaller helpers.
const std = @import("std");
const Io = std.Io;

const discovery = @import("android_discovery/discovery.zig");
const emulator = @import("android_discovery/emulator.zig");
const selection = @import("android_discovery/selection.zig");
const types = @import("types.zig");

/// Discovers connected Android devices via `adb devices -l`.
pub fn discoverAndroidDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.AndroidDevice {
    return discovery.discoverAndroidDevices(arena, io, stderr);
}

/// Discovers available Android Virtual Device profile names.
pub fn discoverAndroidAvds(arena: std.mem.Allocator, io: std.Io) ![]const []const u8 {
    return discovery.discoverAndroidAvds(arena, io);
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
    return selection.chooseAndroidTarget(arena, io, stderr, stdout, devices, avds, selector_raw, non_interactive);
}

/// Starts an AVD profile in detached emulator process.
pub fn startAvd(io: std.Io, stderr: *Io.Writer, avd_name: []const u8) !void {
    return emulator.startAvd(io, stderr, avd_name);
}

/// Waits until a newly-started AVD appears in `adb devices`.
pub fn waitForStartedEmulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    existing_devices: []const types.AndroidDevice,
    avd_name: []const u8,
) !types.AndroidDevice {
    return emulator.waitForStartedEmulator(arena, io, stderr, existing_devices, avd_name);
}

test {
    std.testing.refAllDecls(@import("android_discovery/discovery.zig"));
    std.testing.refAllDecls(@import("android_discovery/emulator.zig"));
    std.testing.refAllDecls(@import("android_discovery/selection.zig"));
}
