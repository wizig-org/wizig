//! User-facing reporting for completed codegen passes.
const std = @import("std");
const Io = std.Io;

const contract_source = @import("../contract/source.zig");
const host_sync = @import("host_sync.zig");
const output_plan = @import("output_plan.zig");
const output_write = @import("output_write.zig");

/// Returns the user-facing label for a resolved contract source.
pub fn sourceLabel(maybe_source: ?contract_source.ApiContractSource) []const u8 {
    return if (maybe_source) |source|
        if (source == .zig) "zig contract + discovery" else "json contract + discovery"
    else
        "auto-discovery";
}

/// Returns whether any generated output changed during the pass.
pub fn hasGeneratedChanges(result: output_write.WriteResult) bool {
    return result.zig_changed or
        result.zig_ffi_changed or
        result.zig_app_module_changed or
        result.swift_changed or
        result.kotlin_changed or
        result.android_jni_bridge_changed or
        result.android_jni_cmake_changed or
        result.ios_mirror_changed or
        result.sdk_swift_changed or
        result.sdk_ios_runtime_changed or
        result.sdk_kotlin_changed or
        result.ios_c_artifacts.changed;
}

/// Writes the codegen summary for generated outputs and patched hosts.
pub fn writeGenerationReport(
    stdout: *Io.Writer,
    maybe_source: ?contract_source.ApiContractSource,
    plan: output_plan.OutputPlan,
    result: output_write.WriteResult,
    sync_result: host_sync.SyncResult,
) !void {
    if (hasGeneratedChanges(result)) {
        try stdout.print("generated API bindings ({s})\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}", .{
            sourceLabel(maybe_source),
            plan.zig_file,
            plan.zig_ffi_root_file,
            plan.zig_app_module_file,
            plan.swift_file,
            plan.kotlin_file,
            plan.android_jni_bridge_file,
            plan.android_jni_cmake_file,
        });
        try stdout.print("\n- {s}\n- {s}\n- {s}\n- {s}", .{
            result.ios_c_artifacts.paths.generated_api_header,
            result.ios_c_artifacts.paths.framework_header,
            result.ios_c_artifacts.paths.modulemap,
            result.ios_c_artifacts.paths.canonical_header,
        });
        if (plan.ios_mirror_swift_file) |mirror_path| try stdout.print("\n- {s}", .{mirror_path});
        if (plan.sdk_swift_file) |sdk_path| try stdout.print("\n- {s}", .{sdk_path});
        if (plan.sdk_ios_runtime_file) |sdk_path| try stdout.print("\n- {s}", .{sdk_path});
        if (plan.sdk_kotlin_file) |sdk_path| try stdout.print("\n- {s}", .{sdk_path});
        try stdout.writeAll("\n");
    } else {
        try stdout.print("API bindings unchanged ({s})\n", .{sourceLabel(maybe_source)});
    }

    if (sync_result.ios_host_patch_summary.patched_projects > 0) {
        try stdout.print(
            "updated iOS host FFI build phase in {d}/{d} project(s)\n",
            .{
                sync_result.ios_host_patch_summary.patched_projects,
                sync_result.ios_host_patch_summary.scanned_projects,
            },
        );
    }
    if (sync_result.android_host_patch_summary.patched) {
        try stdout.writeAll("updated Android host Gradle FFI task compatibility in app/build.gradle.kts\n");
    }
    try stdout.flush();
}

test "sourceLabel maps codegen source kinds" {
    try std.testing.expectEqualStrings("auto-discovery", sourceLabel(null));
    try std.testing.expectEqualStrings("zig contract + discovery", sourceLabel(.zig));
    try std.testing.expectEqualStrings("json contract + discovery", sourceLabel(.json));
}

test "writeGenerationReport prints changed outputs and host updates" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const plan: output_plan.OutputPlan = .{
        .generated_root = ".wizig/generated",
        .zig_file = "zig",
        .zig_ffi_root_file = "ffi",
        .zig_app_module_file = "appmod",
        .swift_file = "swift",
        .kotlin_file = "kotlin",
        .android_jni_bridge_file = "bridge",
        .android_jni_cmake_file = "cmake",
        .ios_mirror_swift_file = "mirror",
        .sdk_swift_file = "sdk-swift",
        .sdk_ios_runtime_file = "sdk-runtime",
        .sdk_kotlin_file = "sdk-kotlin",
    };
    const result: output_write.WriteResult = .{
        .zig_changed = true,
        .zig_ffi_changed = false,
        .zig_app_module_changed = false,
        .swift_changed = false,
        .kotlin_changed = false,
        .android_jni_bridge_changed = false,
        .android_jni_cmake_changed = false,
        .ios_mirror_changed = false,
        .sdk_swift_changed = false,
        .sdk_ios_runtime_changed = false,
        .sdk_kotlin_changed = false,
        .ios_c_artifacts = .{
            .changed = false,
            .paths = .{
                .generated_api_header = "api-h",
                .framework_header = "framework-h",
                .modulemap = "modulemap",
                .canonical_header = "canonical",
            },
        },
    };
    const sync_result: host_sync.SyncResult = .{
        .ios_host_patch_summary = .{ .scanned_projects = 2, .patched_projects = 1 },
        .android_host_patch_summary = .{ .patched = true },
    };

    try writeGenerationReport(&writer.writer, .zig, plan, result, sync_result);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "generated API bindings (zig contract + discovery)") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "- mirror") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "updated iOS host FFI build phase in 1/2 project(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "updated Android host Gradle FFI task compatibility") != null);
}
