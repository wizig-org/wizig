//! iOS FFI build and bundling support for simulators and real devices.
//!
//! This facade keeps the long-lived public API stable while delegating the
//! implementation to focused submodules under `ios_ffi/`.
const std = @import("std");
const Io = std.Io;

const build = @import("ios_ffi/build.zig");
const bundle = @import("ios_ffi/bundle.zig");
const resolve = @import("ios_ffi/resolve.zig");

/// Detailed result for embedding the framework into an app bundle.
pub const BundleResult = bundle.BundleResult;

/// Builds or reuses the cached iOS simulator FFI framework binary.
pub fn buildIosSimulatorFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
    return build.buildIosSimulatorFfiLibrary(arena, io, stderr, parent_environ_map, project_root);
}

/// Builds or reuses the cached iOS device FFI framework binary.
pub fn buildIosDeviceFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
    return build.buildIosDeviceFfiLibrary(arena, io, stderr, parent_environ_map, project_root);
}

/// Copies a host framework into a device app bundle and signs it when needed.
///
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
    return bundle.bundleIosFfiLibraryForDeviceDetailed(
        arena,
        io,
        stderr,
        app_path,
        host_ffi_path,
        sign_identity,
    );
}

/// Copies a host framework into a simulator app bundle.
///
/// Destination files are only rewritten when the bytes differ.
pub fn bundleIosFfiLibraryForSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
    return bundle.bundleIosFfiLibraryForSimulator(arena, io, stderr, app_path, host_ffi_path);
}

/// Resolves an existing iOS FFI library path from the environment or `zig-out`.
pub fn resolveIosFfiLibraryPath(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
    return resolve.resolveIosFfiLibraryPath(arena, io, parent_environ_map);
}
