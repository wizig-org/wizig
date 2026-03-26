//! iOS FFI build orchestration helpers.
//!
//! This module resolves SDK paths, computes cache fingerprints, and invokes
//! `zig build-lib` for the simulator and device framework variants.
const std = @import("std");
const Io = std.Io;

const ffi_fingerprint = @import("../ffi_fingerprint.zig");
const fs_utils = @import("../fs_utils.zig");
const process = @import("../process_supervisor.zig");
const workspace_runtime = @import("../workspace_runtime.zig");
const framework = @import("framework.zig");

const BuildPlan = struct {
    cache_version: []const u8,
    cache_dir: []const u8,
    sdk_name: []const u8,
    sdk_resolution_label: []const u8,
    empty_sdk_error: []const u8,
    target_triple: []const u8,
    run_label: []const u8,
};

const simulator_plan = BuildPlan{
    .cache_version = ffi_fingerprint.ios_ffi_cache_version,
    .cache_dir = "/tmp/wizig-ffi-iossim-cache",
    .sdk_name = "iphonesimulator",
    .sdk_resolution_label = "resolve iOS simulator SDK path",
    .empty_sdk_error = "error: xcrun returned an empty iOS simulator SDK path\n",
    .target_triple = "aarch64-ios-simulator",
    .run_label = "build iOS simulator Wizig FFI library",
};

const device_plan = BuildPlan{
    .cache_version = "wizig-ios-ffi-device-cache-v2",
    .cache_dir = "/tmp/wizig-ffi-iosdev-cache",
    .sdk_name = "iphoneos",
    .sdk_resolution_label = "resolve iOS device SDK path",
    .empty_sdk_error = "error: xcrun returned an empty iOS device SDK path\n",
    .target_triple = "aarch64-ios",
    .run_label = "build iOS device Wizig FFI library",
};

/// Builds or reuses the cached iOS simulator FFI framework binary.
pub fn buildIosSimulatorFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
    return buildCachedFfiLibrary(arena, io, stderr, parent_environ_map, project_root, simulator_plan);
}

/// Builds or reuses the cached iOS device FFI framework binary.
pub fn buildIosDeviceFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
    return buildCachedFfiLibrary(arena, io, stderr, parent_environ_map, project_root, device_plan);
}

/// Resolves the SDK path, fingerprints the inputs, and emits the framework.
fn buildCachedFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
    plan: BuildPlan,
) ![]const u8 {
    const ffi_inputs = try workspace_runtime.resolveFfiBuildInputs(arena, io, stderr, parent_environ_map, project_root);
    const sdk_path = try resolveSdkPath(arena, io, stderr, plan.sdk_name, plan.sdk_resolution_label, plan.empty_sdk_error);

    const fingerprint = try ffi_fingerprint.computeFfiFingerprint(
        arena,
        io,
        plan.cache_version,
        sdk_path,
        ffi_inputs.root_source,
        ffi_inputs.core_source,
        ffi_inputs.app_fingerprint_roots,
    );
    const out_dir = try std.fmt.allocPrint(arena, "{s}/{s}", .{ plan.cache_dir, fingerprint });
    std.Io.Dir.cwd().createDirPath(io, out_dir) catch {};

    const framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ out_dir, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, framework_dir) catch {};

    const out_path = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ framework_dir, std.fs.path.sep_str });
    const info_plist = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ framework_dir, std.fs.path.sep_str });
    if (fs_utils.pathExists(io, out_path)) {
        // Keep cached framework metadata fresh so installer validations do not
        // inherit stale identifiers from old cache versions.
        try framework.writeFrameworkInfoPlist(io, info_plist);
        return out_path;
    }

    const emit_arg = try std.fmt.allocPrint(arena, "-femit-bin={s}", .{out_path});
    const root_arg = try std.fmt.allocPrint(arena, "-Mroot={s}", .{ffi_inputs.root_source});
    const core_arg = try std.fmt.allocPrint(arena, "-Mwizig_core={s}", .{ffi_inputs.core_source});
    const app_arg = if (ffi_inputs.app_source) |app_source| try std.fmt.allocPrint(arena, "-Mwizig_app={s}", .{app_source}) else null;

    var argv = std.ArrayList([]const u8).empty;
    try argv.appendSlice(arena, &.{
        "zig",
        "build-lib",
        "-dynamic",
        "-OReleaseFast",
        "-fno-error-tracing",
        "-fno-unwind-tables",
        "-fstrip",
        "-target",
        plan.target_triple,
        "--dep",
        "wizig_core",
    });
    if (app_arg != null) {
        try argv.appendSlice(arena, &.{ "--dep", "wizig_app" });
    }
    try argv.appendSlice(arena, &.{ root_arg, core_arg });
    if (app_arg) |arg| {
        try argv.append(arena, arg);
    }
    try argv.appendSlice(arena, &.{
        "--name",
        "WizigFFI",
        "--sysroot",
        sdk_path,
        "-L/usr/lib",
        "-F/System/Library/Frameworks",
        "-lc",
        emit_arg,
    });

    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = argv.items,
        .label = plan.run_label,
    }, .{});
    try framework.fixMachoTextPageAlignment(io, out_path);
    try framework.writeFrameworkInfoPlist(io, info_plist);

    return out_path;
}

/// Resolves the Xcode SDK path for the given SDK name.
fn resolveSdkPath(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    sdk_name: []const u8,
    sdk_resolution_label: []const u8,
    empty_sdk_error: []const u8,
) ![]const u8 {
    const sdk = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcrun", "--sdk", sdk_name, "--show-sdk-path" },
        .label = sdk_resolution_label,
    }, .{});
    const sdk_path = std.mem.trim(u8, sdk.stdout, " \t\r\n");
    if (sdk_path.len == 0) {
        try stderr.writeAll(empty_sdk_error);
        return error.RunFailed;
    }
    return sdk_path;
}
