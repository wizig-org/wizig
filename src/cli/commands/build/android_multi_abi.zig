//! Multi-ABI Android FFI build support for Play Store distribution.
//!
//! Iterates over a set of target ABIs, invokes Zig cross-compilation for each,
//! and places outputs in the correct `jniLibs/{abi}/` directories.

const std = @import("std");
const Io = std.Io;

/// Default ABIs for Play Store release builds.
pub const release_abis: []const []const u8 = &.{
    "arm64-v8a",
    "armeabi-v7a",
    "x86_64",
};

/// Maps Android ABI to the corresponding Zig target triple.
pub fn zigTargetForAbi(abi: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, abi, "arm64-v8a")) return "aarch64-linux-android";
    if (std.mem.eql(u8, abi, "armeabi-v7a")) return "arm-linux-androideabi";
    if (std.mem.eql(u8, abi, "x86_64")) return "x86_64-linux-android";
    if (std.mem.eql(u8, abi, "x86")) return "x86-linux-android";
    return null;
}

/// Result of building all ABI slices.
pub const MultiBuildResult = struct {
    built_abis: []const []const u8,
    jni_libs_root: []const u8,
};

/// Builds FFI shared libraries for each ABI using Zig cross-compilation.
pub fn buildMultiAbiFfi(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    ffi_root_source: []const u8,
    core_source: []const u8,
    app_source: ?[]const u8,
    abis: []const []const u8,
    is_release: bool,
) !MultiBuildResult {
    const jni_libs_root = try std.fmt.allocPrint(arena, "{s}/android/app/src/main/jniLibs", .{project_root});

    var built = std.ArrayList([]const u8).empty;

    for (abis) |abi| {
        const zig_target = zigTargetForAbi(abi) orelse {
            try stderr.print("error: unsupported Android ABI: {s}\n", .{abi});
            return error.BuildFailed;
        };

        const abi_dir = try std.fmt.allocPrint(arena, "{s}/{s}", .{ jni_libs_root, abi });
        std.Io.Dir.cwd().createDirPath(io, abi_dir) catch {};

        const out_path = try std.fmt.allocPrint(arena, "{s}/libwizigffi.so", .{abi_dir});
        const emit_arg = try std.fmt.allocPrint(arena, "-femit-bin={s}", .{out_path});
        const root_arg = try std.fmt.allocPrint(arena, "-Mroot={s}", .{ffi_root_source});
        const core_arg = try std.fmt.allocPrint(arena, "-Mwizig_core={s}", .{core_source});
        const app_arg = if (app_source) |s| try std.fmt.allocPrint(arena, "-Mwizig_app={s}", .{s}) else null;

        const optimize: []const u8 = if (is_release) "-OReleaseFast" else "-ODebug";

        var argv = std.ArrayList([]const u8).empty;
        try argv.appendSlice(arena, &.{
            "zig",
            "build-lib",
            optimize,
            "-fno-error-tracing",
            "-fno-unwind-tables",
            "-target",
            zig_target,
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
            "-lc",
        });
        if (is_release) {
            try argv.append(arena, "-fstrip");
        }
        try argv.append(arena, emit_arg);

        try stdout.print("building FFI for {s}...\n", .{abi});
        try stdout.flush();

        const result = std.process.run(arena, io, .{
            .argv = argv.items,
        }) catch |err| {
            try stderr.print("error: failed to build FFI for {s}: {s}\n", .{ abi, @errorName(err) });
            return error.BuildFailed;
        };
        if (!termIsSuccess(result.term)) {
            try stderr.print("error: zig build-lib failed for {s}\n", .{abi});
            if (result.stderr.len > 0) {
                try stderr.writeAll(result.stderr);
            }
            return error.BuildFailed;
        }

        try built.append(arena, try arena.dupe(u8, abi));
    }

    return .{
        .built_abis = try built.toOwnedSlice(arena),
        .jni_libs_root = jni_libs_root,
    };
}

fn termIsSuccess(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "zigTargetForAbi maps supported values" {
    try std.testing.expectEqualStrings("aarch64-linux-android", zigTargetForAbi("arm64-v8a").?);
    try std.testing.expectEqualStrings("arm-linux-androideabi", zigTargetForAbi("armeabi-v7a").?);
    try std.testing.expectEqualStrings("x86_64-linux-android", zigTargetForAbi("x86_64").?);
    try std.testing.expect(zigTargetForAbi("mips64") == null);
}
