//! Shared codegen fingerprint/manifest helpers for fast incremental generation.
const std = @import("std");
const fs_util = @import("fs.zig");

pub const auto_discovery_contract_path = "__auto_discovery__";
pub const fingerprint_version = "wizig-codegen-v9";
pub const manifest_schema_version: u32 = 1;

/// Persistent cache metadata describing the last successful codegen state.
pub const Manifest = struct {
    schema_version: u32,
    fingerprint_version: []const u8,
    fingerprint: []const u8,
    contract_path: []const u8,
    lib_source_count: usize,
    generated_at_unix_ms: i64,
};

/// Snapshot for one project's current codegen input state.
pub const ProjectSnapshot = struct {
    fingerprint: []u8,
    contract_path: []const u8,
    lib_source_paths: []const []const u8,
};

/// Computes current codegen fingerprint inputs for a project.
pub fn computeProjectSnapshot(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    contract_path: ?[]const u8,
) !ProjectSnapshot {
    const resolved_contract_path = contract_path orelse auto_discovery_contract_path;
    const contract_text = if (contract_path) |path|
        try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1024 * 1024))
    else
        "";
    const lib_source_paths = try collectLibZigSourcePaths(arena, io, project_root);
    const fingerprint = try computeCodegenFingerprint(
        arena,
        io,
        project_root,
        resolved_contract_path,
        contract_text,
        lib_source_paths,
    );

    return .{
        .fingerprint = fingerprint,
        .contract_path = resolved_contract_path,
        .lib_source_paths = lib_source_paths,
    };
}

/// Computes a stable hash for contract + discovered source tree metadata.
pub fn computeCodegenFingerprint(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    contract_path: []const u8,
    contract_text: []const u8,
    lib_source_paths: []const []const u8,
) ![]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(fingerprint_version);
    hasher.update(&[_]u8{0});
    hasher.update(contract_path);
    hasher.update(&[_]u8{0});
    hasher.update(contract_text);

    for (lib_source_paths) |source_path| {
        const abs = try std.fs.path.resolve(arena, &.{ project_root, "lib", source_path });
        defer arena.free(abs);

        const stat = std.Io.Dir.cwd().statFile(io, abs, .{}) catch null;
        hasher.update(&[_]u8{0});
        hasher.update(source_path);
        hasher.update(&[_]u8{0});
        if (stat) |meta| {
            var token_buf: [128]u8 = undefined;
            const token = try std.fmt.bufPrint(
                &token_buf,
                "size={d};mtime={d};ctime={d}",
                .{ meta.size, meta.mtime.toNanoseconds(), meta.ctime.toNanoseconds() },
            );
            hasher.update(token);
        } else {
            hasher.update("missing");
        }
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return arena.dupe(u8, &hex);
}

/// Returns true when all required generated API outputs currently exist.
pub fn requiredCodegenOutputsExist(io: std.Io, project_root: []const u8) bool {
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
        if (!fs_util.pathExists(io, abs)) return false;
    }
    return true;
}

/// Reads previously persisted manifest from `.wizig/cache` if present and valid.
pub fn readManifest(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?Manifest {
    const path = try manifestPath(arena, project_root);
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };

    const parsed = std.json.parseFromSlice(std.json.Value, arena, text, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const obj = parsed.value.object;

    const schema_version = jsonObjectU32(obj, "schema_version") orelse return null;
    const manifest_fingerprint_version = jsonObjectString(obj, "fingerprint_version") orelse return null;
    const manifest_fingerprint = jsonObjectString(obj, "fingerprint") orelse return null;
    const contract_path = jsonObjectString(obj, "contract_path") orelse return null;
    const lib_source_count = jsonObjectUsize(obj, "lib_source_count") orelse return null;
    const generated_at_unix_ms = jsonObjectI64(obj, "generated_at_unix_ms") orelse return null;

    return .{
        .schema_version = schema_version,
        .fingerprint_version = try arena.dupe(u8, manifest_fingerprint_version),
        .fingerprint = try arena.dupe(u8, manifest_fingerprint),
        .contract_path = try arena.dupe(u8, contract_path),
        .lib_source_count = lib_source_count,
        .generated_at_unix_ms = generated_at_unix_ms,
    };
}

/// Persists manifest and legacy fingerprint cache files after successful codegen.
pub fn writeManifest(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    manifest: Manifest,
) !void {
    const path = try manifestPath(arena, project_root);

    const payload = .{
        .schema_version = manifest.schema_version,
        .fingerprint_version = manifest.fingerprint_version,
        .fingerprint = manifest.fingerprint,
        .contract_path = manifest.contract_path,
        .lib_source_count = manifest.lib_source_count,
        .generated_at_unix_ms = manifest.generated_at_unix_ms,
    };

    var out: std.Io.Writer.Allocating = .init(arena);
    defer out.deinit();
    try std.json.Stringify.value(payload, .{}, &out.writer);
    try fs_util.writeFileAtomically(io, path, out.written());

    const legacy_path = try legacyFingerprintPath(arena, project_root);
    try fs_util.writeFileAtomically(io, legacy_path, manifest.fingerprint);
}

/// Reads the legacy `.wizig/cache/codegen.sha256` value when present.
pub fn readLegacyFingerprint(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const path = try legacyFingerprintPath(arena, project_root);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(512)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    return std.mem.trim(u8, raw, " \t\r\n");
}

/// Enumerates `lib/**/*.zig` in lexical order and normalized slash format.
pub fn collectLibZigSourcePaths(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
    const lib_root = try std.fs.path.resolve(arena, &.{ project_root, "lib" });
    if (!fs_util.pathExists(io, lib_root)) return &.{};

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
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;

        const rel = try arena.dupe(u8, entry.path);
        for (rel) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        try paths.append(arena, rel);
    }

    std.mem.sort([]const u8, paths.items, {}, lessString);
    return paths.toOwnedSlice(arena);
}

/// Builds `<project_root>/.wizig/cache/codegen.manifest.json`.
pub fn manifestPath(arena: std.mem.Allocator, project_root: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        arena,
        "{s}{s}.wizig{s}cache{s}codegen.manifest.json",
        .{ project_root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );
}

/// Builds `<project_root>/.wizig/cache/codegen.sha256` (legacy compatibility).
pub fn legacyFingerprintPath(arena: std.mem.Allocator, project_root: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        arena,
        "{s}{s}.wizig{s}cache{s}codegen.sha256",
        .{ project_root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );
}

fn jsonObjectString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn jsonObjectI64(object: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .integer => |n| n,
        else => null,
    };
}

fn jsonObjectU32(object: std.json.ObjectMap, key: []const u8) ?u32 {
    const n = jsonObjectI64(object, key) orelse return null;
    if (n < 0) return null;
    return @intCast(n);
}

fn jsonObjectUsize(object: std.json.ObjectMap, key: []const u8) ?usize {
    const n = jsonObjectI64(object, key) orelse return null;
    if (n < 0) return null;
    return @intCast(n);
}

fn lessString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

test "manifest roundtrip persists key fields" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    const project_root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try writeManifest(arena, io, project_root, .{
        .schema_version = manifest_schema_version,
        .fingerprint_version = fingerprint_version,
        .fingerprint = "abc123",
        .contract_path = auto_discovery_contract_path,
        .lib_source_count = 4,
        .generated_at_unix_ms = 1234,
    });

    const loaded = (try readManifest(arena, io, project_root)).?;
    try std.testing.expectEqual(@as(u32, manifest_schema_version), loaded.schema_version);
    try std.testing.expectEqualStrings(fingerprint_version, loaded.fingerprint_version);
    try std.testing.expectEqualStrings("abc123", loaded.fingerprint);
    try std.testing.expectEqualStrings(auto_discovery_contract_path, loaded.contract_path);
    try std.testing.expectEqual(@as(usize, 4), loaded.lib_source_count);
    try std.testing.expectEqual(@as(i64, 1234), loaded.generated_at_unix_ms);
}
