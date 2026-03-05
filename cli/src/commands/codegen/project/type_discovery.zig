//! User-type discovery from `lib/**/*.zig`.
//!
//! ## Responsibilities
//! - Walk `lib/` and discover all public struct/enum declarations.
//! - Build a global type-name registry before parsing fields.
//! - Parse full definitions and reject conflicting duplicates by name.
//! - Expose registry slices used by method discovery and renderers.

const std = @import("std");
const api = @import("../model/api.zig");
const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const parse = @import("type_discovery_parse.zig");

/// Collected user-defined type information discovered from app sources.
pub const TypeRegistry = struct {
    /// Fully parsed user struct definitions.
    structs: []const api.UserStruct,
    /// Fully parsed user enum definitions.
    enums: []const api.UserEnum,
    /// Flattened struct names for fast type-token resolution.
    struct_names: []const []const u8,
    /// Flattened enum names for fast type-token resolution.
    enum_names: []const []const u8,
};

/// Discovers user structs/enums from `project_root/lib/**/*.zig`.
///
/// Parsing runs in two passes:
/// 1. collect all type names (for cross-file field references),
/// 2. parse concrete definitions and validate duplicates.
pub fn discoverLibTypes(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !TypeRegistry {
    const lib_dir = try path_util.join(arena, project_root, "lib");
    if (!fs_util.pathExists(io, lib_dir)) return emptyRegistry();

    var lib = std.Io.Dir.cwd().openDir(io, lib_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return emptyRegistry(),
        else => return err,
    };
    defer lib.close(io);

    var walker = try lib.walk(arena);
    defer walker.deinit();

    var rel_paths = std.ArrayList([]const u8).empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        if (std.mem.eql(u8, entry.path, "WizigGeneratedAppModule.zig")) continue;
        try rel_paths.append(arena, try arena.dupe(u8, entry.path));
    }
    std.mem.sort([]const u8, rel_paths.items, {}, lessString);

    var struct_names = std.ArrayList([]const u8).empty;
    var enum_names = std.ArrayList([]const u8).empty;
    for (rel_paths.items) |rel_path| {
        const source = try readSourceFile(arena, io, lib_dir, rel_path);
        const names = try parse.collectTypeNamesFromSource(arena, source);
        for (names.struct_names) |name| try appendUniqueName(arena, &struct_names, name);
        for (names.enum_names) |name| try appendUniqueName(arena, &enum_names, name);
    }

    const known_struct_names = try struct_names.toOwnedSlice(arena);
    const known_enum_names = try enum_names.toOwnedSlice(arena);

    var all_structs = std.ArrayList(api.UserStruct).empty;
    var all_enums = std.ArrayList(api.UserEnum).empty;
    for (rel_paths.items) |rel_path| {
        const source = try readSourceFile(arena, io, lib_dir, rel_path);

        for (try parse.parseEnumsFromSource(arena, source)) |candidate| {
            try appendOrValidateEnum(arena, &all_enums, candidate);
        }
        for (try parse.parseStructsFromSource(arena, source, known_struct_names, known_enum_names)) |candidate| {
            try appendOrValidateStruct(arena, &all_structs, candidate);
        }
    }

    return .{
        .structs = try all_structs.toOwnedSlice(arena),
        .enums = try all_enums.toOwnedSlice(arena),
        .struct_names = known_struct_names,
        .enum_names = known_enum_names,
    };
}

/// Convenience wrapper used by parser-focused tests.
pub fn parseStructsFromSource(arena: std.mem.Allocator, source: []const u8) ![]const api.UserStruct {
    const names = try parse.collectTypeNamesFromSource(arena, source);
    return parse.parseStructsFromSource(arena, source, names.struct_names, names.enum_names);
}

/// Convenience wrapper used by parser-focused tests.
pub const parseEnumsFromSource = parse.parseEnumsFromSource;

/// Field-token resolution helper re-exported for tests and call sites.
pub const parseFieldType = parse.parseFieldType;

fn emptyRegistry() TypeRegistry {
    return .{
        .structs = &.{},
        .enums = &.{},
        .struct_names = &.{},
        .enum_names = &.{},
    };
}

fn readSourceFile(
    arena: std.mem.Allocator,
    io: std.Io,
    lib_dir: []const u8,
    rel_path: []const u8,
) ![]const u8 {
    const abs_path = try path_util.join(arena, lib_dir, rel_path);
    return std.Io.Dir.cwd().readFileAlloc(io, abs_path, arena, .limited(2 * 1024 * 1024));
}

fn appendUniqueName(
    arena: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
    name: []const u8,
) !void {
    for (out.items) |existing| {
        if (std.mem.eql(u8, existing, name)) return;
    }
    try out.append(arena, name);
}

fn appendOrValidateStruct(
    arena: std.mem.Allocator,
    out: *std.ArrayList(api.UserStruct),
    candidate: api.UserStruct,
) !void {
    for (out.items) |existing| {
        if (!std.mem.eql(u8, existing.name, candidate.name)) continue;
        if (!eqlStructDefinition(existing, candidate)) return error.InvalidContract;
        return;
    }
    try out.append(arena, candidate);
}

fn appendOrValidateEnum(
    arena: std.mem.Allocator,
    out: *std.ArrayList(api.UserEnum),
    candidate: api.UserEnum,
) !void {
    for (out.items) |existing| {
        if (!std.mem.eql(u8, existing.name, candidate.name)) continue;
        if (!eqlEnumDefinition(existing, candidate)) return error.InvalidContract;
        return;
    }
    try out.append(arena, candidate);
}

fn eqlStructDefinition(lhs: api.UserStruct, rhs: api.UserStruct) bool {
    if (lhs.fields.len != rhs.fields.len) return false;
    for (lhs.fields, rhs.fields) |lhs_field, rhs_field| {
        if (!std.mem.eql(u8, lhs_field.name, rhs_field.name)) return false;
        if (!eqlApiType(lhs_field.field_type, rhs_field.field_type)) return false;
    }
    return true;
}

fn eqlEnumDefinition(lhs: api.UserEnum, rhs: api.UserEnum) bool {
    if (lhs.variants.len != rhs.variants.len) return false;
    for (lhs.variants, rhs.variants) |lhs_variant, rhs_variant| {
        if (!std.mem.eql(u8, lhs_variant, rhs_variant)) return false;
    }
    return true;
}

fn eqlApiType(lhs: api.ApiType, rhs: api.ApiType) bool {
    return switch (lhs) {
        .string => switch (rhs) {
            .string => true,
            else => false,
        },
        .int => switch (rhs) {
            .int => true,
            else => false,
        },
        .bool => switch (rhs) {
            .bool => true,
            else => false,
        },
        .void => switch (rhs) {
            .void => true,
            else => false,
        },
        .user_struct => |lhs_name| switch (rhs) {
            .user_struct => |rhs_name| std.mem.eql(u8, lhs_name, rhs_name),
            else => false,
        },
        .user_enum => |lhs_name| switch (rhs) {
            .user_enum => |rhs_name| std.mem.eql(u8, lhs_name, rhs_name),
            else => false,
        },
    };
}

fn lessString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

test {
    _ = @import("type_discovery_tests.zig");
}
