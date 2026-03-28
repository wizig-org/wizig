//! User-type registry assembly for `lib/**/*.zig`.
const std = @import("std");

const api = @import("../../model/api.zig");
const parse = @import("../type_discovery_parse.zig");
const walk = @import("walk.zig");
const fs_util = @import("../../../../support/fs.zig");
const path_util = @import("../../../../support/path.zig");

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

/// Discovers user structs and enums from `project_root/lib/**/*.zig`.
pub fn discoverLibTypes(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !TypeRegistry {
    const rel_paths = try walk.discoverLibSourcePaths(arena, io, project_root);
    if (rel_paths.len == 0) return emptyRegistry();

    const lib_dir = try path_util.join(arena, project_root, "lib");

    var struct_names = std.ArrayList([]const u8).empty;
    var enum_names = std.ArrayList([]const u8).empty;
    for (rel_paths) |rel_path| {
        const source = try readSourceFile(arena, io, lib_dir, rel_path);
        const names = try parse.collectTypeNamesFromSource(arena, source);
        for (names.struct_names) |name| try appendUniqueName(arena, &struct_names, name);
        for (names.enum_names) |name| try appendUniqueName(arena, &enum_names, name);
    }

    const known_struct_names = try struct_names.toOwnedSlice(arena);
    const known_enum_names = try enum_names.toOwnedSlice(arena);

    var all_structs = std.ArrayList(api.UserStruct).empty;
    var all_enums = std.ArrayList(api.UserEnum).empty;
    for (rel_paths) |rel_path| {
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

test "appendUniqueName keeps the first occurrence only" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var names = std.ArrayList([]const u8).empty;
    defer names.deinit(arena);

    try appendUniqueName(arena, &names, "Color");
    try appendUniqueName(arena, &names, "Color");
    try appendUniqueName(arena, &names, "Status");

    try std.testing.expectEqual(@as(usize, 2), names.items.len);
    try std.testing.expectEqualStrings("Color", names.items[0]);
    try std.testing.expectEqualStrings("Status", names.items[1]);
}

test "appendOrValidateStruct rejects conflicting duplicate definitions" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var structs = std.ArrayList(api.UserStruct).empty;
    defer structs.deinit(arena);

    const baseline = api.UserStruct{
        .name = "Profile",
        .fields = &.{
            .{ .name = "name", .field_type = .string },
        },
    };
    const conflicting = api.UserStruct{
        .name = "Profile",
        .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "age", .field_type = .int },
        },
    };

    try appendOrValidateStruct(arena, &structs, baseline);
    try std.testing.expectError(error.InvalidContract, appendOrValidateStruct(arena, &structs, conflicting));
}

test "discoverLibTypes merges unique names from multiple files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();
    const io = std.testing.io;

    const project_root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/sample-app", .{tmp.sub_path});
    const lib_dir = try path_util.join(arena, project_root, "lib");
    try std.Io.Dir.cwd().createDirPath(io, lib_dir);

    try fs_util.writeFileAtomically(io, try path_util.join(arena, lib_dir, "a.zig"),
        \\pub const Color = enum {
        \\    red,
        \\};
        \\
        \\pub const Profile = struct {
        \\    favorite: Color,
        \\};
    );
    try fs_util.writeFileAtomically(io, try path_util.join(arena, lib_dir, "b.zig"),
        \\pub const Status = enum {
        \\    active,
        \\};
    );

    const registry = try discoverLibTypes(arena, io, project_root);
    try std.testing.expectEqual(@as(usize, 1), registry.structs.len);
    try std.testing.expectEqual(@as(usize, 2), registry.enums.len);
    try std.testing.expectEqual(@as(usize, 1), registry.struct_names.len);
    try std.testing.expectEqual(@as(usize, 2), registry.enum_names.len);
}
