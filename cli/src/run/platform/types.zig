//! Run platform domain model types.
//!
//! This module defines the structured data that is shared across the
//! platform-specific run pipeline. Keeping these types isolated avoids circular
//! imports between Android/iOS flow modules and process utilities.
const std = @import("std");

/// Public run command error set used by platform execution code.
pub const RunError = error{RunFailed};

/// Target platform selector parsed from CLI arguments.
pub const Platform = enum {
    ios,
    android,
};

/// Debugger and monitor mode selected for the run command.
pub const DebuggerMode = enum {
    auto,
    lldb,
    jdb,
    logcat,
    none,
};

/// Parsed and normalized options for platform run execution.
pub const RunOptions = struct {
    platform: Platform,
    project_dir: []const u8,

    device_selector: ?[]const u8 = null,
    debugger: DebuggerMode = .auto,
    non_interactive: bool = false,
    once: bool = false,
    monitor_timeout_seconds: ?u64 = null,
    regenerate_host: bool = false,
    skip_device_discovery: bool = false,
    skip_codegen: bool = false,

    // iOS options.
    scheme: ?[]const u8 = null,
    bundle_id: ?[]const u8 = null,

    // Android options.
    module: []const u8 = "app",
    app_id: ?[]const u8 = null,
    activity: ?[]const u8 = null,
};

/// iOS simulator selection model returned by discovery.
pub const IosDevice = struct {
    name: []const u8,
    udid: []const u8,
    runtime: []const u8,
    state: []const u8,
};

/// Android target model returned by `adb devices -l` parsing.
pub const AndroidDevice = struct {
    serial: []const u8,
    model: []const u8,
    state: []const u8,
};

/// Android run target union supporting a connected device or an AVD profile.
pub const AndroidTarget = union(enum) {
    device: AndroidDevice,
    avd: []const u8,
};

/// Inputs used to build per-platform Wizig FFI artifacts.
pub const FfiBuildInputs = struct {
    root_source: []const u8,
    core_source: []const u8,
    app_source: ?[]const u8 = null,
    app_fingerprint_roots: []const []const u8 = &.{},
};
