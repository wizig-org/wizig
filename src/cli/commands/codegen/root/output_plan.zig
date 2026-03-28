//! Generated output path planning for codegen.
const std = @import("std");

const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const project_paths = @import("../project/paths.zig");

/// Filesystem plan for generated code and SDK mirror outputs.
pub const OutputPlan = struct {
    generated_root: []const u8,
    zig_file: []const u8,
    zig_ffi_root_file: []const u8,
    zig_app_module_file: []const u8,
    swift_file: []const u8,
    kotlin_file: []const u8,
    android_jni_bridge_file: []const u8,
    android_jni_cmake_file: []const u8,
    ios_mirror_swift_file: ?[]const u8,
    sdk_swift_file: ?[]const u8,
    sdk_ios_runtime_file: ?[]const u8,
    sdk_kotlin_file: ?[]const u8,
};

/// Resolves output paths and ensures the generated directories exist.
pub fn prepare(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !OutputPlan {
    const generated_root = try path_util.join(arena, project_root, ".wizig/generated");
    const zig_dir = try path_util.join(arena, generated_root, "zig");
    const swift_dir = try path_util.join(arena, generated_root, "swift");
    const kotlin_dir = try path_util.join(arena, generated_root, "kotlin/dev/wizig");
    const android_jni_dir = try path_util.join(arena, generated_root, "android/jni");

    try fs_util.ensureDir(io, zig_dir);
    try fs_util.ensureDir(io, swift_dir);
    try fs_util.ensureDir(io, kotlin_dir);
    try fs_util.ensureDir(io, android_jni_dir);

    return .{
        .generated_root = generated_root,
        .zig_file = try path_util.join(arena, zig_dir, "WizigGeneratedApi.zig"),
        .zig_ffi_root_file = try path_util.join(arena, zig_dir, "WizigGeneratedFfiRoot.zig"),
        .zig_app_module_file = try path_util.join(arena, project_root, "lib/WizigGeneratedAppModule.zig"),
        .swift_file = try path_util.join(arena, swift_dir, "WizigGeneratedApi.swift"),
        .kotlin_file = try path_util.join(arena, kotlin_dir, "WizigGeneratedApi.kt"),
        .android_jni_bridge_file = try path_util.join(arena, android_jni_dir, "WizigGeneratedApiBridge.c"),
        .android_jni_cmake_file = try path_util.join(arena, android_jni_dir, "CMakeLists.txt"),
        .ios_mirror_swift_file = try project_paths.resolveIosMirrorSwiftFile(arena, io, project_root),
        .sdk_swift_file = try project_paths.resolveSdkSwiftApiFile(arena, io, project_root),
        .sdk_ios_runtime_file = try project_paths.resolveSdkIosRuntimeFile(arena, io, project_root),
        .sdk_kotlin_file = try project_paths.resolveSdkKotlinApiFile(arena, io, project_root),
    };
}
