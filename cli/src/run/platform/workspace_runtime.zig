//! Runtime/workspace resolution for Wizig FFI builds.
//!
//! This module resolves which runtime source tree should be used for FFI build
//! steps and returns canonical input paths for incremental fingerprinting.
const std = @import("std");
const Io = std.Io;

const fs_utils = @import("fs_utils.zig");
const text_utils = @import("text_utils.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

/// Resolves all source inputs needed to build Wizig FFI artifacts.
pub fn resolveFfiBuildInputs(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) !types.FfiBuildInputs {
    const runtime_root = try resolveWizigWorkspaceRoot(arena, io, parent_environ_map, project_root, stderr);
    const runtime_core = try std.fmt.allocPrint(
        arena,
        "{s}{s}core{s}src{s}root.zig",
        .{ runtime_root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );

    const generated_ffi_root = try std.fs.path.resolve(arena, &.{ project_root, ".wizig", "generated", "zig", "WizigGeneratedFfiRoot.zig" });
    const generated_app_module = try std.fs.path.resolve(arena, &.{ project_root, "lib", "WizigGeneratedAppModule.zig" });
    const fallback_app_source = try std.fs.path.resolve(arena, &.{ project_root, "lib", "main.zig" });
    const lib_root = try std.fs.path.resolve(arena, &.{ project_root, "lib" });
    const generated_zig_root = try std.fs.path.resolve(arena, &.{ project_root, ".wizig", "generated", "zig" });
    const runtime_ffi = try std.fmt.allocPrint(
        arena,
        "{s}{s}ffi{s}src{s}root.zig",
        .{ runtime_root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );

    if (fs_utils.pathExists(io, generated_ffi_root) and fs_utils.pathExists(io, runtime_core)) {
        const app_source = if (fs_utils.pathExists(io, generated_app_module)) generated_app_module else fallback_app_source;
        if (!fs_utils.pathExists(io, app_source) or !fs_utils.pathExists(io, runtime_ffi)) {
            try stderr.writeAll("error: missing app/runtime sources for generated FFI root\n");
            return error.RunFailed;
        }

        var fingerprint_roots = std.ArrayList([]const u8).empty;
        if (fs_utils.pathExists(io, lib_root)) {
            try fingerprint_roots.append(arena, lib_root);
        }
        if (fs_utils.pathExists(io, generated_zig_root)) {
            try fingerprint_roots.append(arena, generated_zig_root);
        }

        return .{
            .root_source = generated_ffi_root,
            .core_source = runtime_core,
            .app_source = app_source,
            .app_fingerprint_roots = try fingerprint_roots.toOwnedSlice(arena),
        };
    }

    if (!fs_utils.pathExists(io, runtime_ffi) or !fs_utils.pathExists(io, runtime_core)) {
        try stderr.writeAll("error: missing runtime sources for FFI build\n");
        return error.RunFailed;
    }

    return .{
        .root_source = runtime_ffi,
        .core_source = runtime_core,
    };
}

/// Resolves the runtime workspace root from app-local, env, or host hints.
pub fn resolveWizigWorkspaceRoot(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    project_dir: []const u8,
    stderr: *Io.Writer,
) ![]const u8 {
    if (try resolveAppLocalRuntimeRoot(arena, io, project_dir)) |runtime_root| {
        return runtime_root;
    }

    if (parent_environ_map.get("WIZIG_SDK_ROOT")) |raw_root| {
        const resolved = if (std.fs.path.isAbsolute(raw_root))
            try arena.dupe(u8, raw_root)
        else blk: {
            const cwd = try std.process.currentPathAlloc(io, arena);
            break :blk try std.fs.path.resolve(arena, &.{ cwd, raw_root });
        };
        const marker = try std.fmt.allocPrint(
            arena,
            "{s}{s}ffi{s}src{s}root.zig",
            .{ resolved, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
        );
        if (fs_utils.pathExists(io, marker)) return resolved;
    }

    if (try extractWizigWorkspaceFromProjectYml(arena, io, project_dir)) |root| {
        return root;
    }

    const cwd = try std.process.currentPathAlloc(io, arena);
    const cwd_marker = try std.fmt.allocPrint(
        arena,
        "{s}{s}ffi{s}src{s}root.zig",
        .{ cwd, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );
    if (fs_utils.pathExists(io, cwd_marker)) return cwd;

    try stderr.writeAll(
        "error: unable to resolve Wizig runtime root; expected app-local .wizig/runtime or set WIZIG_SDK_ROOT\n",
    );
    return error.RunFailed;
}

fn resolveAppLocalRuntimeRoot(arena: Allocator, io: std.Io, project_dir: []const u8) !?[]const u8 {
    const direct = try std.fs.path.resolve(arena, &.{ project_dir, ".wizig", "runtime" });
    if (runtimeRootLooksValid(arena, io, direct)) return direct;

    const parent = std.fs.path.dirname(project_dir) orelse return null;
    const parent_candidate = try std.fs.path.resolve(arena, &.{ parent, ".wizig", "runtime" });
    if (runtimeRootLooksValid(arena, io, parent_candidate)) return parent_candidate;

    return null;
}

fn runtimeRootLooksValid(arena: Allocator, io: std.Io, root: []const u8) bool {
    const marker_core = std.fmt.allocPrint(
        arena,
        "{s}{s}core{s}src{s}root.zig",
        .{ root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    ) catch return false;
    const marker_ffi = std.fmt.allocPrint(
        arena,
        "{s}{s}ffi{s}src{s}root.zig",
        .{ root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    ) catch return false;
    return fs_utils.pathExists(io, marker_core) and fs_utils.pathExists(io, marker_ffi);
}

fn extractWizigWorkspaceFromProjectYml(
    arena: Allocator,
    io: std.Io,
    project_dir: []const u8,
) !?[]const u8 {
    const project_yml_path = try std.fmt.allocPrint(arena, "{s}{s}project.yml", .{ project_dir, std.fs.path.sep_str });
    const content = std.Io.Dir.cwd().readFileAlloc(io, project_yml_path, arena, .limited(512 * 1024)) catch return null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, "path:")) continue;

        const raw_value = std.mem.trim(u8, line["path:".len..], " \t\r");
        const value = text_utils.trimOptionalQuotes(raw_value);
        if (value.len == 0) continue;

        const sdk_path = if (std.fs.path.isAbsolute(value))
            try arena.dupe(u8, value)
        else
            try std.fs.path.resolve(arena, &.{ project_dir, value });

        const sdk_norm = try arena.dupe(u8, sdk_path);
        for (sdk_norm) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }

        const suffix = "/sdk/ios";
        if (!std.mem.endsWith(u8, sdk_norm, suffix)) continue;
        if (sdk_norm.len <= suffix.len) continue;

        const root = try arena.dupe(u8, sdk_path[0 .. sdk_path.len - suffix.len]);
        const marker = try std.fmt.allocPrint(
            arena,
            "{s}{s}ffi{s}src{s}root.zig",
            .{ root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
        );
        if (fs_utils.pathExists(io, marker)) return root;
    }

    return null;
}
