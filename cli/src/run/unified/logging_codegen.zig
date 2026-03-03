//! Unified run logging and codegen preflight helpers.
//!
//! This module writes per-run metadata logs and ensures code generation is
//! executed only when source/contract fingerprints change.
const std = @import("std");
const Io = std.Io;

const codegen_cmd = @import("../../commands/codegen/root.zig");
const fs_utils = @import("../platform/fs_utils.zig");

const codegen_fingerprint_version = "wizig-codegen-v7";

/// Builds the unified run log path under `<project>/.wizig/logs/run.log`.
pub fn buildLogPath(arena: std.mem.Allocator, io: std.Io, project_root: []const u8) ![]const u8 {
    const logs_dir = try std.fmt.allocPrint(arena, "{s}{s}.wizig{s}logs", .{ project_root, std.fs.path.sep_str, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, logs_dir) catch {};
    return std.fmt.allocPrint(arena, "{s}{s}run.log", .{ logs_dir, std.fs.path.sep_str });
}

/// Appends a formatted line to the in-memory run log buffer.
pub fn appendLogLine(
    arena: std.mem.Allocator,
    log_lines: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const line = try std.fmt.allocPrint(arena, fmt, args);
    try log_lines.appendSlice(arena, line);
}

/// Executes codegen only when the fingerprint differs from cached state.
pub fn runCodegenPreflight(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    log_lines: *std.ArrayList(u8),
) !void {
    const contract = try codegen_cmd.resolveApiContract(arena, io, stderr, project_root, null);
    const contract_path = if (contract) |resolved| resolved.path else "__auto_discovery__";
    const contract_text = if (contract) |resolved|
        std.Io.Dir.cwd().readFileAlloc(io, resolved.path, arena, .limited(1024 * 1024)) catch |err| {
            try appendLogLine(arena, log_lines, "codegen=failed:read_contract:{s}\n", .{@errorName(err)});
            try stderr.print("error: failed to read API contract '{s}': {s}\n", .{ resolved.path, @errorName(err) });
            try stderr.flush();
            return error.RunFailed;
        }
    else
        "";
    const lib_source_paths = try collectLibZigSourcePaths(arena, io, project_root);
    const fingerprint = try computeCodegenFingerprint(arena, io, project_root, contract_path, contract_text, lib_source_paths);
    const cache_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}.wizig{s}cache{s}codegen.sha256",
        .{ project_root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );

    if (fs_utils.pathExists(io, cache_path)) {
        const cached_raw = std.Io.Dir.cwd().readFileAlloc(io, cache_path, arena, .limited(512)) catch "";
        const cached = std.mem.trim(u8, cached_raw, " \t\r\n");
        if (std.mem.eql(u8, cached, fingerprint) and requiredCodegenOutputsExist(io, project_root)) {
            try appendLogLine(arena, log_lines, "codegen=skipped:fingerprint\n", .{});
            try stdout.writeAll("codegen up-to-date (fingerprint match)\n");
            try stdout.flush();
            return;
        }
    }

    try appendLogLine(arena, log_lines, "codegen=running\n", .{});
    try stdout.writeAll("running codegen...\n");
    try stdout.flush();

    codegen_cmd.generateProject(arena, io, stderr, stdout, project_root, if (contract) |resolved| resolved.path else null) catch |err| {
        try appendLogLine(arena, log_lines, "codegen=failed:{s}\n", .{@errorName(err)});
        if (contract) |resolved| {
            try stderr.print("error: failed to generate API bindings from '{s}': {s}\n", .{ resolved.path, @errorName(err) });
        } else {
            try stderr.print("error: failed to generate API bindings from discovered lib methods: {s}\n", .{@errorName(err)});
        }
        try stderr.flush();
        return error.RunFailed;
    };

    try appendLogLine(arena, log_lines, "codegen=ok\n", .{});
    try fs_utils.writeFileAtomically(io, cache_path, fingerprint);
}

fn computeCodegenFingerprint(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    contract_path: []const u8,
    contract_text: []const u8,
    lib_source_paths: []const []const u8,
) ![]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(codegen_fingerprint_version);
    hasher.update(&[_]u8{0});
    hasher.update(contract_path);
    hasher.update(&[_]u8{0});
    hasher.update(contract_text);
    for (lib_source_paths) |source_path| {
        const abs = try std.fs.path.resolve(arena, &.{ project_root, "lib", source_path });
        defer arena.free(abs);

        const bytes = std.Io.Dir.cwd().readFileAlloc(io, abs, arena, .limited(1024 * 1024)) catch null;
        hasher.update(&[_]u8{0});
        hasher.update(source_path);
        hasher.update(&[_]u8{0});
        if (bytes) |owned| {
            defer arena.free(owned);
            hasher.update(owned);
        }
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return arena.dupe(u8, &hex);
}

fn requiredCodegenOutputsExist(io: std.Io, project_root: []const u8) bool {
    const required_paths = [_][]const u8{
        ".wizig/generated/zig/WizigGeneratedApi.zig",
        ".wizig/generated/zig/WizigGeneratedFfiRoot.zig",
        "lib/WizigGeneratedAppModule.zig",
        ".wizig/generated/swift/WizigGeneratedApi.swift",
        ".wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt",
        ".wizig/generated/android/jni/WizigGeneratedApiBridge.c",
        ".wizig/generated/android/jni/CMakeLists.txt",
    };
    for (required_paths) |rel| {
        const abs = std.fs.path.resolve(std.heap.page_allocator, &.{ project_root, rel }) catch return false;
        defer std.heap.page_allocator.free(abs);
        if (!fs_utils.pathExists(io, abs)) return false;
    }
    return true;
}

fn collectLibZigSourcePaths(arena: std.mem.Allocator, io: std.Io, project_root: []const u8) ![]const []const u8 {
    const lib_root = try std.fs.path.resolve(arena, &.{ project_root, "lib" });
    if (!fs_utils.pathExists(io, lib_root)) return &.{};

    var lib_dir = std.Io.Dir.cwd().openDir(io, lib_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer lib_dir.close(io);

    var walker = try lib_dir.walk(arena);
    defer walker.deinit();

    var paths = std.ArrayList([]const u8).empty;
    errdefer paths.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".zig")) continue;

        const rel = try arena.dupe(u8, entry.path);
        for (rel) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        try paths.append(arena, rel);
    }

    std.mem.sort([]const u8, paths.items, {}, lessString);
    return paths.toOwnedSlice(arena);
}

fn lessString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

test "computeCodegenFingerprint is stable and content-sensitive" {
    const first = try computeCodegenFingerprint(std.testing.allocator, std.testing.io, ".", "/tmp/wizig.api.zig", "pub const namespace = \"x\";\n", &.{});
    defer std.testing.allocator.free(first);
    const second = try computeCodegenFingerprint(std.testing.allocator, std.testing.io, ".", "/tmp/wizig.api.zig", "pub const namespace = \"x\";\n", &.{});
    defer std.testing.allocator.free(second);
    const changed = try computeCodegenFingerprint(std.testing.allocator, std.testing.io, ".", "/tmp/wizig.api.zig", "pub const namespace = \"y\";\n", &.{});
    defer std.testing.allocator.free(changed);

    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(!std.mem.eql(u8, first, changed));
}
