//! iOS C interop artifact generation for framework packaging.
//!
//! This module writes generated headers/modulemap under `.wizig/generated/ios`
//! so the Xcode build phase can package an App Store-safe XCFramework that is
//! discoverable by Swift/ObjC IDE tooling.

const std = @import("std");
const api = @import("../model/api.zig");
const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const ios_c_headers = @import("../render/ios_c_headers.zig");

/// File paths for generated iOS framework interop artifacts.
pub const GeneratedPaths = struct {
    generated_api_header: []const u8,
    framework_header: []const u8,
    modulemap: []const u8,
    canonical_header: []const u8,
};

/// Result of generating iOS framework interop artifacts.
pub const GenerateResult = struct {
    changed: bool,
    paths: GeneratedPaths,
};

/// Writes iOS C headers and modulemap for the current project API surface.
pub fn generate(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *std.Io.Writer,
    project_root: []const u8,
    generated_root: []const u8,
    spec: api.ApiSpec,
) !GenerateResult {
    const generated_ios_dir = try path_util.join(arena, generated_root, "ios");
    try fs_util.ensureDir(io, generated_ios_dir);

    const generated_api_header = try path_util.join(arena, generated_ios_dir, "WizigGeneratedApi.h");
    const framework_header = try path_util.join(arena, generated_ios_dir, "WizigFFI.h");
    const modulemap = try path_util.join(arena, generated_ios_dir, "module.modulemap");
    const canonical_header = try path_util.join(arena, generated_ios_dir, "wizig.h");

    const rendered_api_header = try ios_c_headers.renderGeneratedApiHeader(arena, spec);
    const rendered_framework_header = try ios_c_headers.renderFrameworkUmbrellaHeader(arena);
    const rendered_modulemap = try ios_c_headers.renderFrameworkModuleMap(arena);

    const source_runtime_header = try path_util.join(arena, project_root, ".wizig/runtime/ffi/include/wizig.h");
    if (!fs_util.pathExists(io, source_runtime_header)) {
        try stderr.print(
            "error: missing runtime FFI header required for iOS framework packaging: {s}\n",
            .{source_runtime_header},
        );
        return error.CodegenFailed;
    }

    const canonical_header_contents = std.Io.Dir.cwd().readFileAlloc(
        io,
        source_runtime_header,
        arena,
        .limited(1024 * 1024),
    ) catch |err| {
        try stderr.print(
            "error: failed to read runtime FFI header '{s}': {s}\n",
            .{ source_runtime_header, @errorName(err) },
        );
        return error.CodegenFailed;
    };

    const api_header_changed = try fs_util.writeFileIfChanged(arena, io, generated_api_header, rendered_api_header);
    const framework_header_changed = try fs_util.writeFileIfChanged(arena, io, framework_header, rendered_framework_header);
    const modulemap_changed = try fs_util.writeFileIfChanged(arena, io, modulemap, rendered_modulemap);
    const canonical_header_changed = try fs_util.writeFileIfChanged(arena, io, canonical_header, canonical_header_contents);

    return .{
        .changed = api_header_changed or framework_header_changed or modulemap_changed or canonical_header_changed,
        .paths = .{
            .generated_api_header = generated_api_header,
            .framework_header = framework_header,
            .modulemap = modulemap,
            .canonical_header = canonical_header,
        },
    };
}
