//! iOS FFI build and bundling support for simulators and real devices.
//!
//! This module builds cached dynamic framework binaries and installs
//! `WizigFFI.framework` into app bundle locations expected by runtime loaders.
const std = @import("std");
const Io = std.Io;

const ffi_fingerprint = @import("ffi_fingerprint.zig");
const fs_utils = @import("fs_utils.zig");
const process = @import("process_supervisor.zig");
const workspace_runtime = @import("workspace_runtime.zig");

/// Builds or reuses cached iOS simulator FFI framework binary for the current app.
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

    const framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ out_dir, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, framework_dir) catch {};

    const out_path = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ framework_dir, std.fs.path.sep_str });
    const info_plist = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ framework_dir, std.fs.path.sep_str });
    if (fs_utils.pathExists(io, out_path)) {
        // Keep cached framework metadata fresh so installer validations do not
        // inherit stale identifiers from old cache versions.
        try writeFrameworkInfoPlist(io, info_plist);
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
        .label = "build iOS simulator Wizig FFI library",
    }, .{});
    try writeFrameworkInfoPlist(io, info_plist);

    return out_path;
}

/// Builds or reuses cached iOS device FFI framework binary for the current app.
pub fn buildIosDeviceFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
    const ffi_inputs = try workspace_runtime.resolveFfiBuildInputs(arena, io, stderr, parent_environ_map, project_root);

    const sdk = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcrun", "--sdk", "iphoneos", "--show-sdk-path" },
        .label = "resolve iOS device SDK path",
    }, .{});
    const sdk_path = std.mem.trim(u8, sdk.stdout, " \t\r\n");
    if (sdk_path.len == 0) {
        try stderr.writeAll("error: xcrun returned an empty iOS device SDK path\n");
        return error.RunFailed;
    }

    const fingerprint = try ffi_fingerprint.computeFfiFingerprint(
        arena,
        io,
        "wizig-ios-ffi-device-cache-v2",
        sdk_path,
        ffi_inputs.root_source,
        ffi_inputs.core_source,
        ffi_inputs.app_fingerprint_roots,
    );
    const out_dir = try std.fmt.allocPrint(arena, "/tmp/wizig-ffi-iosdev-cache/{s}", .{fingerprint});
    std.Io.Dir.cwd().createDirPath(io, out_dir) catch {};

    const framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ out_dir, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, framework_dir) catch {};

    const out_path = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ framework_dir, std.fs.path.sep_str });
    const info_plist = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ framework_dir, std.fs.path.sep_str });
    if (fs_utils.pathExists(io, out_path)) {
        try writeFrameworkInfoPlist(io, info_plist);
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
        "aarch64-ios",
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
        .label = "build iOS device Wizig FFI library",
    }, .{});
    try writeFrameworkInfoPlist(io, info_plist);

    return out_path;
}

/// Copies host dynamic framework into device app `Frameworks` location.
///
/// ## Signing
/// Device installations require embedded frameworks to be code signed with the
/// same identity used for the app bundle.
pub fn bundleIosFfiLibraryForDevice(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
    sign_identity: ?[]const u8,
) ![]const u8 {
    const frameworks_dir = try std.fmt.allocPrint(arena, "{s}{s}Frameworks", .{ app_path, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, frameworks_dir) catch {};

    const src_framework_dir = std.fs.path.dirname(host_ffi_path) orelse {
        try stderr.writeAll("error: invalid host iOS FFI framework path\n");
        return error.RunFailed;
    };
    const dst_framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ frameworks_dir, std.fs.path.sep_str });
    const frameworks_ffi = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ dst_framework_dir, std.fs.path.sep_str });
    const src_info = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ src_framework_dir, std.fs.path.sep_str });
    const dst_info = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ dst_framework_dir, std.fs.path.sep_str });

    const binary_changed = !try filesEqual(arena, io, host_ffi_path, frameworks_ffi);
    const plist_changed = !try filesEqual(arena, io, src_info, dst_info);
    const changed_frameworks = binary_changed or plist_changed;

    if (changed_frameworks) {
        _ = process.runCapture(arena, io, .{
            .argv = &.{ "rm", "-rf", dst_framework_dir },
            .label = "remove previous iOS device framework staging",
        }, .{}) catch {};
        _ = try process.runCaptureChecked(arena, io, stderr, .{
            .argv = &.{ "cp", "-R", src_framework_dir, dst_framework_dir },
            .label = "copy Wizig framework into iOS device app Frameworks",
        }, .{});

        if (sign_identity) |identity| {
            if (identity.len != 0) {
                _ = try process.runCaptureChecked(arena, io, stderr, .{
                    .argv = &.{ "/usr/bin/codesign", "--force", "--sign", identity, "--timestamp=none", dst_framework_dir },
                    .label = "codesign embedded iOS device Wizig framework",
                }, .{});
            }
        }
    }

    return "@executable_path/Frameworks/WizigFFI.framework/WizigFFI";
}

/// Copies host dynamic framework into simulator app `Frameworks` location.
///
/// ## Incrementality
/// Destination files are updated only when bytes differ, preserving filesystem
/// metadata via `cp` while avoiding redundant writes.
pub fn bundleIosFfiLibraryForSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
    const frameworks_dir = try std.fmt.allocPrint(arena, "{s}{s}Frameworks", .{ app_path, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, frameworks_dir) catch {};

    const src_framework_dir = std.fs.path.dirname(host_ffi_path) orelse {
        try stderr.writeAll("error: invalid host iOS FFI framework path\n");
        return error.RunFailed;
    };
    const dst_framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ frameworks_dir, std.fs.path.sep_str });
    const frameworks_ffi = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ dst_framework_dir, std.fs.path.sep_str });
    const src_info = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ src_framework_dir, std.fs.path.sep_str });
    const dst_info = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ dst_framework_dir, std.fs.path.sep_str });

    const binary_changed = !try filesEqual(arena, io, host_ffi_path, frameworks_ffi);
    const plist_changed = !try filesEqual(arena, io, src_info, dst_info);
    const changed_frameworks = binary_changed or plist_changed;

    if (changed_frameworks) {
        _ = process.runCapture(arena, io, .{
            .argv = &.{ "rm", "-rf", dst_framework_dir },
            .label = "remove previous iOS framework staging",
        }, .{}) catch {};
        _ = try process.runCaptureChecked(arena, io, stderr, .{
            .argv = &.{ "cp", "-R", src_framework_dir, dst_framework_dir },
            .label = "copy Wizig framework into iOS app Frameworks",
        }, .{});
    }

    return "@executable_path/Frameworks/WizigFFI.framework/WizigFFI";
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

fn writeFrameworkInfoPlist(io: std.Io, out_path: []const u8) !void {
    const contents =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" ++
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" ++
        "<plist version=\"1.0\">\n" ++
        "<dict>\n" ++
        "    <key>CFBundleDevelopmentRegion</key>\n" ++
        "    <string>en</string>\n" ++
        "    <key>CFBundleExecutable</key>\n" ++
        "    <string>WizigFFI</string>\n" ++
        "    <key>CFBundleIdentifier</key>\n" ++
        "    <string>dev.wizig.WizigFFI.framework</string>\n" ++
        "    <key>CFBundleInfoDictionaryVersion</key>\n" ++
        "    <string>6.0</string>\n" ++
        "    <key>CFBundleName</key>\n" ++
        "    <string>WizigFFI</string>\n" ++
        "    <key>CFBundlePackageType</key>\n" ++
        "    <string>FMWK</string>\n" ++
        "    <key>CFBundleShortVersionString</key>\n" ++
        "    <string>1.0</string>\n" ++
        "    <key>CFBundleVersion</key>\n" ++
        "    <string>1</string>\n" ++
        "</dict>\n" ++
        "</plist>\n";
    try fs_utils.writeFileAtomically(io, out_path, contents);
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
    const framework_guess = try std.fs.path.resolve(arena, &.{ cwd, "zig-out", "lib", "WizigFFI.framework", "WizigFFI" });
    if (fs_utils.pathExists(io, framework_guess)) return framework_guess;
    const static_guess = try std.fs.path.resolve(arena, &.{ cwd, "zig-out", "lib", "libWizigFFI.a" });
    if (fs_utils.pathExists(io, static_guess)) return static_guess;
    return null;
}
