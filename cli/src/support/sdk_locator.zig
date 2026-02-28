//! SDK/runtime/template locator for portable Wizig installs.
const std = @import("std");
const Io = std.Io;
const fs_util = @import("fs.zig");
const path_util = @import("path.zig");

/// Resolved directories required to scaffold and run projects.
pub const ResolvedSdk = struct {
    root: []const u8,
    sdk_dir: []const u8,
    runtime_dir: []const u8,
    templates_dir: []const u8,
};

/// Resolves Wizig SDK roots using CLI/env/install/dev fallback precedence.
pub fn resolve(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    explicit_root: ?[]const u8,
) !ResolvedSdk {
    var attempts = std.ArrayList([]const u8).empty;
    defer attempts.deinit(arena);

    if (explicit_root) |raw| {
        const candidate = try path_util.resolveAbsolute(arena, io, raw);
        try attempts.append(arena, candidate);
        if (isValidRoot(arena, io, candidate)) {
            return buildResolved(arena, candidate);
        }
    }

    if (env_map.get("WIZIG_SDK_ROOT")) |raw| {
        const candidate = try path_util.resolveAbsolute(arena, io, raw);
        try attempts.append(arena, candidate);
        if (isValidRoot(arena, io, candidate)) {
            return buildResolved(arena, candidate);
        }
    }

    if (std.process.executablePathAlloc(io, arena)) |exe_path| {
        const exe_dir = try path_util.parentDirAlloc(arena, exe_path);

        const bundled_share = try std.fs.path.resolve(arena, &.{ exe_dir, "..", "share", "wizig" });
        try attempts.append(arena, bundled_share);
        if (isValidRoot(arena, io, bundled_share)) {
            return buildResolved(arena, bundled_share);
        }

        const bundled_resources = try std.fs.path.resolve(arena, &.{ exe_dir, "..", "Resources", "wizig" });
        try attempts.append(arena, bundled_resources);
        if (isValidRoot(arena, io, bundled_resources)) {
            return buildResolved(arena, bundled_resources);
        }
    } else |_| {}

    const cwd = try std.process.currentPathAlloc(io, arena);
    var probe = try arena.dupe(u8, cwd);
    while (true) {
        try attempts.append(arena, probe);
        if (isValidRoot(arena, io, probe)) {
            return buildResolved(arena, probe);
        }
        const parent = std.fs.path.dirname(probe) orelse break;
        if (std.mem.eql(u8, parent, probe)) break;
        probe = try arena.dupe(u8, parent);
    }

    try stderr.writeAll("error: unable to resolve Wizig SDK root\n");
    for (attempts.items) |attempt| {
        try stderr.print("  attempted: {s}\n", .{attempt});
    }
    try stderr.writeAll(
        "hint: pass --sdk-root <wizig_root> or set WIZIG_SDK_ROOT; expected markers under root: sdk/, runtime/, templates/\n",
    );
    return error.NotFound;
}

fn buildResolved(arena: std.mem.Allocator, root: []const u8) !ResolvedSdk {
    const sdk_dir = try path_util.join(arena, root, "sdk");
    const runtime_dir = try path_util.join(arena, root, "runtime");
    const templates_dir = try path_util.join(arena, root, "templates");
    return .{
        .root = root,
        .sdk_dir = sdk_dir,
        .runtime_dir = runtime_dir,
        .templates_dir = templates_dir,
    };
}

fn isValidRoot(arena: std.mem.Allocator, io: std.Io, root: []const u8) bool {
    const marker_a = path_util.join(arena, root, "sdk/ios/Package.swift") catch return false;
    const marker_b = path_util.join(arena, root, "sdk/android/src/main/kotlin/dev/wizig/WizigRuntime.kt") catch return false;
    const marker_c = path_util.join(arena, root, "runtime/ffi/src/root.zig") catch return false;
    const marker_d = path_util.join(arena, root, "runtime/core/src/root.zig") catch return false;
    const marker_e = path_util.join(arena, root, "templates/app/README.md") catch return false;

    return fs_util.pathExists(io, marker_a) and
        fs_util.pathExists(io, marker_b) and
        fs_util.pathExists(io, marker_c) and
        fs_util.pathExists(io, marker_d) and
        fs_util.pathExists(io, marker_e);
}
