//! Mirrors generated iOS FFI artifacts into the local SwiftPM SDK package.

const std = @import("std");
const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const api = @import("../model/api.zig");
const paths = @import("paths.zig");
const ios_c_headers = @import("../render/ios_c_headers.zig");
const ios_c_shim = @import("../render/ios_c_shim.zig");

/// Mirrors generated C headers + C shim source into `.wizig/sdk/ios/Sources/WizigFFI`.
pub fn mirrorGeneratedIosFfiArtifacts(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    spec: api.ApiSpec,
) !void {
    if (try paths.resolveSdkIosFfiIncludeDir(arena, io, project_root)) |ffi_include_dir| {
        const rendered_api_header = try ios_c_headers.renderGeneratedApiHeader(arena, spec);
        const rendered_framework_header = try ios_c_headers.renderFrameworkUmbrellaHeader(arena);
        _ = try fs_util.writeFileIfChanged(arena, io, try path_util.join(arena, ffi_include_dir, "WizigGeneratedApi.h"), rendered_api_header);
        _ = try fs_util.writeFileIfChanged(arena, io, try path_util.join(arena, ffi_include_dir, "WizigFFI.h"), rendered_framework_header);

        const source_runtime_header = try path_util.join(arena, project_root, ".wizig/runtime/ffi/include/wizig.h");
        if (fs_util.pathExists(io, source_runtime_header)) {
            const canonical = std.Io.Dir.cwd().readFileAlloc(io, source_runtime_header, arena, .limited(1024 * 1024)) catch null;
            if (canonical) |content| {
                _ = try fs_util.writeFileIfChanged(arena, io, try path_util.join(arena, ffi_include_dir, "wizig.h"), content);
            }
        }
    }

    if (try paths.resolveSdkIosFfiStubSource(arena, io, project_root)) |ffi_stub_source| {
        const rendered_ios_shim = try ios_c_shim.renderIosSwiftPmShim(arena, spec);
        _ = try fs_util.writeFileIfChanged(arena, io, ffi_stub_source, rendered_ios_shim);
    }
}
