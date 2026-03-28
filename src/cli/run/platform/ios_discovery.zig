//! iOS simulator and physical device discovery and selection utilities.
//!
//! This facade keeps the public API stable while delegating discovery,
//! parsing, filtering, and selection to smaller testable modules.
const std = @import("std");
const Io = std.Io;

const destinations = @import("ios_discovery/destinations.zig");
const physical = @import("ios_discovery/physical.zig");
const selection = @import("ios_discovery/selection.zig");
const simulator = @import("ios_discovery/simulator.zig");
const types = @import("types.zig");

/// Lists available iOS simulators from `simctl`.
pub fn discoverIosDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.IosDevice {
    return simulator.discoverIosDevices(arena, io, stderr);
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
    return destinations.discoverIosSupportedDestinationIds(arena, io, stderr, project_dir, xcode_project, scheme);
}

/// Lists connected physical iOS devices via `xcrun devicectl`.
pub fn discoverIosPhysicalDevices(arena: std.mem.Allocator, io: std.Io) ![]types.IosDevice {
    return physical.discoverIosPhysicalDevices(arena, io);
}

/// Filters discovered iOS devices by allowed destination IDs.
pub fn filterIosDevicesBySupportedIds(
    arena: std.mem.Allocator,
    devices: []const types.IosDevice,
    supported_ids: []const []const u8,
) ![]types.IosDevice {
    return selection.filterIosDevicesBySupportedIds(arena, devices, supported_ids);
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
    return selection.chooseIosDevice(arena, io, stderr, stdout, devices, selector, non_interactive);
}

test {
    std.testing.refAllDecls(@import("ios_discovery/destinations.zig"));
    std.testing.refAllDecls(@import("ios_discovery/physical.zig"));
    std.testing.refAllDecls(@import("ios_discovery/selection.zig"));
    std.testing.refAllDecls(@import("ios_discovery/simulator.zig"));
}
