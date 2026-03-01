//! iOS simulator FFI build and bundling support.
//!
//! This module builds cached simulator dylibs and installs them into app bundle
//! locations expected by simulator launch environment variables.
const std = @import("std");
const Io = std.Io;

const ffi_fingerprint = @import("ffi_fingerprint.zig");
const fs_utils = @import("fs_utils.zig");
const process = @import("process_supervisor.zig");
const workspace_runtime = @import("workspace_runtime.zig");

/// Builds or reuses cached iOS simulator FFI dylib for the current app.
pub fn buildIosSimulatorFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
    const ffi_inputs = try workspace_runtime.resolveFfiBuildInputs(arena, io, stderr, parent_environ_map, project_root);

    const sdk = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcrun", "--sdk", "iphonesimulator", "--show-sdk-path" },
        .label = "resolve iOS simulator SDK path",
    }, .{});
    const sdk_path = std.mem.trim(u8, sdk.stdout, " \t\r\n");
    if (sdk_path.len == 0) {
        try stderr.writeAll("error: xcrun returned an empty iOS simulator SDK path\n");
        return error.RunFailed;
    }

    const fingerprint = try ffi_fingerprint.computeFfiFingerprint(
        arena,
        io,
        ffi_fingerprint.ios_ffi_cache_version,
        sdk_path,
        ffi_inputs.root_source,
        ffi_inputs.core_source,
        ffi_inputs.app_fingerprint_roots,
    );
    const out_dir = try std.fmt.allocPrint(arena, "/tmp/wizig-ffi-iossim-cache/{s}", .{fingerprint});
    std.Io.Dir.cwd().createDirPath(io, out_dir) catch {};

    const out_path = try std.fmt.allocPrint(arena, "{s}{s}wizigffi", .{ out_dir, std.fs.path.sep_str });
    if (fs_utils.pathExists(io, out_path)) {
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
        "-OReleaseFast",
        "-fno-error-tracing",
        "-fno-unwind-tables",
        "-fstrip",
        "-target",
        "aarch64-ios-simulator",
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
        "wizigffi",
        "-dynamic",
        "-install_name",
        "@rpath/libwizigffi.dylib",
        "--sysroot",
        sdk_path,
        "-L/usr/lib",
        "-F/System/Library/Frameworks",
        "-lc",
        emit_arg,
    });

    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = argv.items,
        .label = "build iOS simulator Wizig FFI library",
    }, .{});

    return out_path;
}

/// Copies host dylib into simulator bundle and framework locations.
pub fn bundleIosFfiLibraryForSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
    const frameworks_dir = try std.fmt.allocPrint(arena, "{s}{s}Frameworks", .{ app_path, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, frameworks_dir) catch {};

    const app_bundle_ffi = try std.fmt.allocPrint(arena, "{s}{s}wizigffi", .{ app_path, std.fs.path.sep_str });
    const frameworks_ffi = try std.fmt.allocPrint(arena, "{s}{s}wizigffi", .{ frameworks_dir, std.fs.path.sep_str });

    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "cp", host_ffi_path, app_bundle_ffi },
        .label = "copy Wizig FFI into iOS app bundle",
    }, .{});
    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "cp", host_ffi_path, frameworks_ffi },
        .label = "copy Wizig FFI into iOS app Frameworks",
    }, .{});

    return "@executable_path/Frameworks/wizigffi";
}

/// Resolves existing iOS FFI library path from environment or default output.
pub fn resolveIosFfiLibraryPath(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
    if (parent_environ_map.get("WIZIG_FFI_LIB")) |raw_path| {
        if (std.fs.path.isAbsolute(raw_path)) {
            if (fs_utils.pathExists(io, raw_path)) return try arena.dupe(u8, raw_path);
        } else {
            const cwd = try std.process.currentPathAlloc(io, arena);
            const resolved = try std.fs.path.resolve(arena, &.{ cwd, raw_path });
            if (fs_utils.pathExists(io, resolved)) return resolved;
        }
    }

    const cwd = try std.process.currentPathAlloc(io, arena);
    const guessed = try std.fs.path.resolve(arena, &.{ cwd, "zig-out", "lib", "libwizigffi.dylib" });
    if (fs_utils.pathExists(io, guessed)) return guessed;
    return null;
}
