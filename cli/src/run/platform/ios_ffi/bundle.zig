//! iOS FFI framework embedding helpers.
//!
//! This module keeps the simulator and device bundle flows aligned while
//! isolating the filesystem copy and code-signing steps from the build logic.
const std = @import("std");
const Io = std.Io;

const framework = @import("framework.zig");
const process = @import("../process_supervisor.zig");

/// Result returned by the framework bundling helpers.
pub const BundleResult = struct {
    /// Dynamic loader path used by the host runtime.
    loader_path: []const u8,
    /// Whether the destination framework contents changed on disk.
    changed: bool,
};

const FrameworkPaths = struct {
    src_binary_path: []const u8,
    src_framework_dir: []const u8,
    dst_framework_dir: []const u8,
    dst_binary_path: []const u8,
    src_info_path: []const u8,
    dst_info_path: []const u8,
};

/// Copies a host framework into a device app bundle and signs it when needed.
pub fn bundleIosFfiLibraryForDevice(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
    sign_identity: ?[]const u8,
) ![]const u8 {
    return (try bundleIosFfiLibraryForDeviceDetailed(
        arena,
        io,
        stderr,
        app_path,
        host_ffi_path,
        sign_identity,
    )).loader_path;
}

/// Copies a host framework into a device app bundle and reports whether it changed.
pub fn bundleIosFfiLibraryForDeviceDetailed(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
    sign_identity: ?[]const u8,
) !BundleResult {
    const paths = try resolveFrameworkPaths(arena, io, stderr, app_path, host_ffi_path);
    const changed = try bundleFrameworkIntoApp(arena, io, stderr, paths, "remove previous iOS device framework staging", "copy Wizig framework into iOS device app Frameworks");
    if (changed) {
        try signEmbeddedFramework(arena, io, stderr, paths.dst_framework_dir, paths.dst_binary_path, sign_identity);
    }
    return .{
        .loader_path = "@executable_path/Frameworks/WizigFFI.framework/WizigFFI",
        .changed = changed,
    };
}

/// Copies a host framework into a simulator app bundle and re-signs.
pub fn bundleIosFfiLibraryForSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
    const paths = try resolveFrameworkPaths(arena, io, stderr, app_path, host_ffi_path);
    const changed = try bundleFrameworkIntoApp(arena, io, stderr, paths, "remove previous iOS framework staging", "copy Wizig framework into iOS app Frameworks");
    if (changed) {
        // Re-sign framework and app bundle after replacing the framework binary,
        // since the copy invalidates the Xcode-produced code signature.
        _ = process.runCapture(arena, io, .{
            .argv = &.{ "/usr/bin/codesign", "-f", "-s", "-", paths.dst_framework_dir },
            .label = "ad-hoc sign simulator framework after bundling",
        }, .{}) catch {};
        _ = process.runCapture(arena, io, .{
            .argv = &.{ "/usr/bin/codesign", "-f", "-s", "-", app_path },
            .label = "ad-hoc re-sign simulator app bundle after framework update",
        }, .{}) catch {};
    }
    return "@executable_path/Frameworks/WizigFFI.framework/WizigFFI";
}

/// Resolves source and destination framework paths for a bundle operation.
fn resolveFrameworkPaths(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) !FrameworkPaths {
    const frameworks_dir = try std.fmt.allocPrint(arena, "{s}{s}Frameworks", .{ app_path, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, frameworks_dir) catch {};

    const src_framework_dir = std.fs.path.dirname(host_ffi_path) orelse {
        try stderr.writeAll("error: invalid host iOS FFI framework path\n");
        return error.RunFailed;
    };
    const dst_framework_dir = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI.framework", .{ frameworks_dir, std.fs.path.sep_str });
    const dst_binary_path = try std.fmt.allocPrint(arena, "{s}{s}WizigFFI", .{ dst_framework_dir, std.fs.path.sep_str });
    const src_info_path = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ src_framework_dir, std.fs.path.sep_str });
    const dst_info_path = try std.fmt.allocPrint(arena, "{s}{s}Info.plist", .{ dst_framework_dir, std.fs.path.sep_str });

    return .{
        .src_binary_path = host_ffi_path,
        .src_framework_dir = src_framework_dir,
        .dst_framework_dir = dst_framework_dir,
        .dst_binary_path = dst_binary_path,
        .src_info_path = src_info_path,
        .dst_info_path = dst_info_path,
    };
}

/// Copies the framework tree when the embedded payload has changed.
fn bundleFrameworkIntoApp(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    paths: FrameworkPaths,
    rm_label: []const u8,
    copy_label: []const u8,
) !bool {
    const binary_changed = !try framework.filesEqual(arena, io, paths.src_binary_path, paths.dst_binary_path);
    const plist_changed = !try framework.filesEqual(arena, io, paths.src_info_path, paths.dst_info_path);
    const changed_frameworks = binary_changed or plist_changed;

    if (changed_frameworks) {
        _ = process.runCapture(arena, io, .{
            .argv = &.{ "rm", "-rf", paths.dst_framework_dir },
            .label = rm_label,
        }, .{}) catch {};
        _ = try process.runCaptureChecked(arena, io, stderr, .{
            .argv = &.{ "cp", "-R", paths.src_framework_dir, paths.dst_framework_dir },
            .label = copy_label,
        }, .{});
    }

    return changed_frameworks;
}

/// Signs the embedded device framework when a code signing identity exists.
fn signEmbeddedFramework(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    dst_framework_dir: []const u8,
    dst_binary_path: []const u8,
    sign_identity: ?[]const u8,
) !void {
    // Strip Zig's ad-hoc signature before applying the real device identity.
    _ = process.runCapture(arena, io, .{
        .argv = &.{ "/usr/bin/codesign", "--remove-signature", dst_binary_path },
        .label = "strip ad-hoc signature from iOS device FFI binary",
    }, .{}) catch {};

    const identity = if (sign_identity) |id| (if (id.len != 0) id else null) else null;
    if (identity) |id| {
        _ = try process.runCaptureChecked(arena, io, stderr, .{
            .argv = &.{ "/usr/bin/codesign", "--force", "--sign", id, "--timestamp=none", dst_framework_dir },
            .label = "codesign embedded iOS device Wizig framework",
        }, .{});
        return;
    }

    try stderr.writeAll("error: no code signing identity available for device build; WizigFFI.framework requires signing for real device installation\n");
    try stderr.writeAll("hint: ensure Xcode automatic signing is configured with a valid development team\n");
    return error.RunFailed;
}
