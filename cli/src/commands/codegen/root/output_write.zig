//! Rendering and file persistence for generated code outputs.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../../../support/fs.zig");
const output_plan = @import("output_plan.zig");
const project_ios_c_artifacts = @import("../project/ios_c_artifacts.zig");
const project_paths = @import("../project/paths.zig");
const render_android_jni_bridge = @import("../render/android_jni_bridge.zig");
const render_android_jni_cmake = @import("../render/android_jni_cmake.zig");
const render_kotlin_api = @import("../render/kotlin_api.zig");
const render_swift_api = @import("../render/swift_api.zig");
const render_zig_api = @import("../render/zig_api.zig");
const render_zig_app_module = @import("../render/zig_app_module.zig");
const render_zig_ffi_root = @import("../render/zig_ffi_root.zig");
const spec_bundle = @import("spec_bundle.zig");

/// Change summary for generated files written in one codegen pass.
pub const WriteResult = struct {
    zig_changed: bool,
    zig_ffi_changed: bool,
    zig_app_module_changed: bool,
    swift_changed: bool,
    kotlin_changed: bool,
    android_jni_bridge_changed: bool,
    android_jni_cmake_changed: bool,
    ios_mirror_changed: bool,
    sdk_swift_changed: bool,
    sdk_ios_runtime_changed: bool,
    sdk_kotlin_changed: bool,
    ios_c_artifacts: project_ios_c_artifacts.GenerateResult,
};

/// Renders all generated outputs and persists them to disk.
pub fn renderAndWrite(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    plan: output_plan.OutputPlan,
    bundle: spec_bundle.SpecBundle,
) !WriteResult {
    const zig_out = try render_zig_api.renderZigApi(arena, bundle.spec);
    const zig_ffi_root_out = try render_zig_ffi_root.renderZigFfiRoot(arena, bundle.spec, bundle.compat);
    const zig_app_module_out = try render_zig_app_module.renderZigAppModule(arena, bundle.spec, bundle.app_module_imports);
    const swift_out = try render_swift_api.renderSwiftApi(arena, bundle.spec, bundle.compat);
    const kotlin_out = try render_kotlin_api.renderKotlinApi(arena, bundle.spec, bundle.compat);
    const android_jni_bridge_out = try render_android_jni_bridge.renderAndroidJniBridge(arena, bundle.spec, bundle.compat);
    const android_jni_cmake_out = try render_android_jni_cmake.renderAndroidJniCmake(arena);

    const ios_c_artifacts = try project_ios_c_artifacts.generate(
        arena,
        io,
        stderr,
        project_root,
        plan.generated_root,
        bundle.spec,
    );

    return .{
        .zig_changed = try fs_util.writeFileIfChanged(arena, io, plan.zig_file, zig_out),
        .zig_ffi_changed = try fs_util.writeFileIfChanged(arena, io, plan.zig_ffi_root_file, zig_ffi_root_out),
        .zig_app_module_changed = try fs_util.writeFileIfChanged(arena, io, plan.zig_app_module_file, zig_app_module_out),
        .swift_changed = try fs_util.writeFileIfChanged(arena, io, plan.swift_file, swift_out),
        .kotlin_changed = try fs_util.writeFileIfChanged(arena, io, plan.kotlin_file, kotlin_out),
        .android_jni_bridge_changed = try fs_util.writeFileIfChanged(arena, io, plan.android_jni_bridge_file, android_jni_bridge_out),
        .android_jni_cmake_changed = try fs_util.writeFileIfChanged(arena, io, plan.android_jni_cmake_file, android_jni_cmake_out),
        .ios_mirror_changed = if (plan.ios_mirror_swift_file) |mirror_path|
            try fs_util.writeFileIfChanged(arena, io, mirror_path, swift_out)
        else
            false,
        .sdk_swift_changed = if (plan.sdk_swift_file) |sdk_path|
            try fs_util.writeFileIfChanged(arena, io, sdk_path, swift_out)
        else
            false,
        .sdk_ios_runtime_changed = try mirrorBundledIosRuntime(arena, io, stderr, plan.sdk_ios_runtime_file),
        .sdk_kotlin_changed = if (plan.sdk_kotlin_file) |sdk_path|
            try fs_util.writeFileIfChanged(arena, io, sdk_path, kotlin_out)
        else
            false,
        .ios_c_artifacts = ios_c_artifacts,
    };
}

/// Mirrors the bundled iOS runtime source into the local Swift SDK package.
fn mirrorBundledIosRuntime(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    sdk_ios_runtime_file: ?[]const u8,
) !bool {
    const sdk_path = sdk_ios_runtime_file orelse return false;
    const source_path = try project_paths.resolveBundledIosRuntimeSource(arena, io) orelse return false;

    const runtime_source = std.Io.Dir.cwd().readFileAlloc(io, source_path, arena, .limited(1024 * 1024)) catch |err| blk: {
        try stderr.print("warning: failed to read iOS runtime source '{s}': {s}\n", .{ source_path, @errorName(err) });
        break :blk null;
    };
    if (runtime_source) |content| {
        return fs_util.writeFileIfChanged(arena, io, sdk_path, content);
    }
    return false;
}
