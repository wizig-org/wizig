//! Android target discovery and selection.
//!
//! This module isolates device and AVD selection so the main flow only deals
//! with the resolved target.
const std = @import("std");
const Io = std.Io;

const android_discovery = @import("../android_discovery.zig");
const android_log_stream = @import("../android_log_stream.zig");
const types = @import("../types.zig");

/// Resolves the Android device to run against, including emulator boot.
pub fn resolveAndroidTarget(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !types.AndroidDevice {
    if (options.skip_device_discovery) {
        return android_log_stream.resolvePreselectedAndroidDevice(arena, stderr, options.device_selector);
    }

    const devices = try android_discovery.discoverAndroidDevices(arena, io, stderr);
    const avds = try android_discovery.discoverAndroidAvds(arena, io);
    if (devices.len == 0 and avds.len == 0) {
        try stderr.writeAll("error: no Android devices and no AVD profiles found\n");
        return error.RunFailed;
    }

    const selected_target = try android_discovery.chooseAndroidTarget(
        arena,
        io,
        stderr,
        stdout,
        devices,
        avds,
        options.device_selector,
        options.non_interactive,
    );

    return switch (selected_target) {
        .device => |device| device,
        .avd => |avd_name| blk: {
            try stdout.print("starting AVD '{s}'...\n", .{avd_name});
            try stdout.flush();
            try android_discovery.startAvd(io, stderr, avd_name);
            const emulator = try android_discovery.waitForStartedEmulator(arena, io, stderr, devices, avd_name);
            break :blk emulator;
        },
    };
}
