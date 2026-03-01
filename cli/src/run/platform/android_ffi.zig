//! Android FFI build and staging pipeline.
//!
//! This module builds ABI-specific Wizig FFI shared libraries, caches results
//! by content fingerprint, and stages artifacts for Android host build usage.
const std = @import("std");
const Io = std.Io;

const ffi_fingerprint = @import("ffi_fingerprint.zig");
const fs_utils = @import("fs_utils.zig");
const process = @import("process_supervisor.zig");
const text_utils = @import("text_utils.zig");
const types = @import("types.zig");
const workspace_runtime = @import("workspace_runtime.zig");

/// Builds and stages Android FFI library for the selected device ABI.
pub fn prepareAndroidFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    app_root: []const u8,
    serial: []const u8,
) !types.AndroidFfiArtifact {
    const abi = try resolveAndroidDeviceAbi(arena, io, stderr, serial);
    const zig_target = zigTargetForAndroidAbi(abi) orelse {
        try stderr.print("error: unsupported Android ABI '{s}'\n", .{abi});
        return error.RunFailed;
    };
    const ffi_inputs = try workspace_runtime.resolveFfiBuildInputs(arena, io, stderr, parent_environ_map, app_root);

    const fingerprint = try ffi_fingerprint.computeFfiFingerprint(
        arena,
        io,
        ffi_fingerprint.android_ffi_cache_version,
        zig_target,
        ffi_inputs.root_source,
        ffi_inputs.core_source,
        ffi_inputs.app_fingerprint_roots,
    );
    const cache_dir = try std.fmt.allocPrint(arena, "/tmp/wizig-ffi-android-cache/{s}", .{fingerprint});
    std.Io.Dir.cwd().createDirPath(io, cache_dir) catch {};

    const cache_path = try std.fmt.allocPrint(arena, "{s}{s}libwizigffi.so", .{ cache_dir, std.fs.path.sep_str });
    if (!fs_utils.pathExists(io, cache_path)) {
        try stdout.print("building Android FFI library for ABI {s}...\n", .{abi});
        try stdout.flush();
        try buildAndroidFfiLibrary(arena, io, stderr, ffi_inputs, zig_target, cache_path);
    }

    const staged_dir = try std.fmt.allocPrint(
        arena,
        "{s}{s}.wizig{s}generated{s}android{s}jniLibs{s}{s}",
        .{ app_root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str, abi },
    );
    std.Io.Dir.cwd().createDirPath(io, staged_dir) catch {};

    const staged_path = try std.fmt.allocPrint(arena, "{s}{s}libwizigffi.so", .{ staged_dir, std.fs.path.sep_str });
    try fs_utils.copyFileIfChanged(arena, io, cache_path, staged_path);

    return .{
        .abi = try arena.dupe(u8, abi),
        .staged_path = staged_path,
    };
}

/// Resolves device ABI using ordered `getprop` probes.
pub fn resolveAndroidDeviceAbi(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    serial: []const u8,
) ![]const u8 {
    const properties = [_][]const u8{
        "ro.product.cpu.abilist64",
        "ro.product.cpu.abilist",
        "ro.product.cpu.abi",
    };

    for (properties) |property| {
        const result = process.runCapture(arena, io, .{
            .argv = &.{ "adb", "-s", serial, "shell", "getprop", property },
            .label = "resolve Android device ABI",
        }, .{}) catch continue;
        if (!process.termIsSuccess(result.term)) continue;

        if (parseFirstSupportedAndroidAbi(result.stdout)) |abi| {
            return arena.dupe(u8, abi);
        }
    }

    try stderr.print("error: failed to resolve Android ABI for device '{s}'\n", .{serial});
    return error.RunFailed;
}

/// Maps Android ABI to the corresponding Zig target triple.
pub fn zigTargetForAndroidAbi(abi: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, abi, "arm64-v8a")) return "aarch64-linux-android";
    if (std.mem.eql(u8, abi, "armeabi-v7a")) return "arm-linux-androideabi";
    if (std.mem.eql(u8, abi, "x86_64")) return "x86_64-linux-android";
    if (std.mem.eql(u8, abi, "x86")) return "x86-linux-android";
    return null;
}

fn parseFirstSupportedAndroidAbi(raw: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, raw, " \t\r\n,");
    while (it.next()) |token| {
        if (zigTargetForAndroidAbi(token) != null) return token;
    }
    return null;
}

fn buildAndroidFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    ffi_inputs: types.FfiBuildInputs,
    zig_target: []const u8,
    cache_path: []const u8,
) !void {
    const root_arg = try std.fmt.allocPrint(arena, "-Mroot={s}", .{ffi_inputs.root_source});
    const core_arg = try std.fmt.allocPrint(arena, "-Mwizig_core={s}", .{ffi_inputs.core_source});
    const app_arg = if (ffi_inputs.app_source) |app_source| try std.fmt.allocPrint(arena, "-Mwizig_app={s}", .{app_source}) else null;
    const emit_arg = try std.fmt.allocPrint(arena, "-femit-bin={s}", .{cache_path});

    var argv = std.ArrayList([]const u8).empty;
    try argv.appendSlice(arena, &.{ "zig", "build-lib", "-OReleaseFast", "-target", zig_target, "--dep", "wizig_core" });
    if (app_arg != null) {
        try argv.appendSlice(arena, &.{ "--dep", "wizig_app" });
    }
    try argv.appendSlice(arena, &.{ root_arg, core_arg });
    if (app_arg) |arg| {
        try argv.append(arena, arg);
    }
    try argv.appendSlice(arena, &.{ "--name", "wizigffi", "-dynamic", emit_arg });

    _ = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = argv.items,
        .label = "build Android Wizig FFI library",
    }, .{});
}
