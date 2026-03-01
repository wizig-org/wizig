//! Domain types for unified run orchestration.
//!
//! These types represent normalized unified run options and discovered platform
//! candidates before delegation into platform-specific execution.
const std = @import("std");

/// Platform label used by unified candidate records.
pub const Platform = enum {
    ios,
    android,
};

/// Parsed options for `wizig run` unified mode.
pub const UnifiedOptions = struct {
    project_root: []const u8 = ".",
    device_selector: ?[]const u8 = null,
    debugger_mode: ?[]const u8 = null,
    non_interactive: bool = false,
    once: bool = false,
    monitor_timeout_seconds: ?u64 = null,
    regenerate_host: bool = false,
};

/// Candidate target selected from iOS/Android discovery results.
pub const Candidate = struct {
    platform: Platform,
    id: []const u8,
    name: []const u8,
    state: []const u8,
    project_dir: []const u8,
};

/// Generic device record used during discovery before candidate conversion.
pub const DeviceInfo = struct {
    id: []const u8,
    name: []const u8,
    state: []const u8,
};

/// Converts platform enum to a stable CLI label.
pub fn platformLabel(platform: Platform) []const u8 {
    return switch (platform) {
        .ios => "ios",
        .android => "android",
    };
}

/// Sort comparator for case-insensitive device name ordering.
pub fn lessDeviceInfo(_: void, a: DeviceInfo, b: DeviceInfo) bool {
    return std.ascii.lessThanIgnoreCase(a.name, b.name);
}
