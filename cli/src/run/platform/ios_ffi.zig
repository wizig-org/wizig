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

/// Copies host dylib into simulator app Frameworks location.
///
/// ## Incrementality
/// Destination files are updated only when bytes differ, preserving filesystem
/// metadata via `cp` while avoiding redundant writes.
///
/// ## Launch Stability
/// On modern simulator runtimes, placing unmanaged dylibs in the app bundle
/// root can fail installation preflight. This function stages the Wizig runtime
/// only in `Frameworks/` and re-signs changed artifacts to satisfy launch
/// policy checks.
pub fn bundleIosFfiLibraryForSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
    const frameworks_dir = try std.fmt.allocPrint(arena, "{s}{s}Frameworks", .{ app_path, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, frameworks_dir) catch {};

    const frameworks_ffi = try std.fmt.allocPrint(arena, "{s}{s}wizigffi", .{ frameworks_dir, std.fs.path.sep_str });

    const changed_frameworks = try copyFileWithCpIfChanged(
        arena,
        io,
        stderr,
        host_ffi_path,
        frameworks_ffi,
        "copy Wizig FFI into iOS app Frameworks",
    );

    if (changed_frameworks) {
        try codesignPath(arena, io, stderr, frameworks_ffi, "codesign staged Wizig FFI in iOS Frameworks");
        try codesignPath(arena, io, stderr, app_path, "codesign iOS app after staging Wizig FFI");
    }

    return "@executable_path/Frameworks/wizigffi";
}

fn copyFileWithCpIfChanged(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    src_path: []const u8,
    dst_path: []const u8,
    label: []const u8,
) !bool {
    if (try filesEqual(arena, io, src_path, dst_path)) return false;

    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "cp", src_path, dst_path },
        .label = label,
    }, .{});
    return true;
}

fn filesEqual(
    arena: std.mem.Allocator,
    io: std.Io,
    src_path: []const u8,
    dst_path: []const u8,
) !bool {
    const src_bytes = try std.Io.Dir.cwd().readFileAlloc(io, src_path, arena, .limited(128 * 1024 * 1024));
    const dst_bytes = std.Io.Dir.cwd().readFileAlloc(io, dst_path, arena, .limited(128 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return std.mem.eql(u8, src_bytes, dst_bytes);
}

fn codesignPath(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    path: []const u8,
    label: []const u8,
) !void {
    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", path },
        .label = label,
    }, .{});
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
