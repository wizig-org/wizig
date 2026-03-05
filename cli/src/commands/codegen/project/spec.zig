//! Project-level API spec defaults and merge behavior.
//!
//! This module merges explicit contract data with discovered code symbols while
//! preserving deterministic ordering and rejecting semantic conflicts.

const std = @import("std");
const api = @import("../model/api.zig");

/// Builds a minimal default API spec for projects with no explicit contract.
pub fn defaultApiSpecForProject(arena: std.mem.Allocator, project_root: []const u8) !api.ApiSpec {
    const tail = std.fs.path.basename(project_root);
    const candidate = if (tail.len > 0) tail else "app";
    const namespace = try std.fmt.allocPrint(arena, "dev.wizig.{s}", .{candidate});
    return .{
        .namespace = namespace,
        .methods = &.{},
        .events = &.{},
        .structs = &.{},
        .enums = &.{},
    };
}

/// Legacy merge entry-point kept for existing call sites.
pub fn mergeSpecWithDiscoveredMethods(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered_methods: []const api.ApiMethod,
) !api.ApiSpec {
    return mergeSpecWithDiscoveredTypes(arena, base_spec, discovered_methods, &.{}, &.{});
}

/// Merges discovered methods and user-defined types into a base spec.
///
/// Conflict rules:
/// - same method name with different signature => `error.InvalidContract`
/// - same struct name with different field schema => `error.InvalidContract`
/// - same enum name with different variants => `error.InvalidContract`
pub fn mergeSpecWithDiscoveredTypes(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered_methods: []const api.ApiMethod,
    discovered_structs: []const api.UserStruct,
    discovered_enums: []const api.UserEnum,
) !api.ApiSpec {
    const merged_methods = try mergeMethods(arena, base_spec.methods, discovered_methods);
    const merged_structs = try mergeStructs(arena, base_spec.structs, discovered_structs);
    const merged_enums = try mergeEnums(arena, base_spec.enums, discovered_enums);

    return .{
        .namespace = base_spec.namespace,
        .methods = merged_methods,
        .events = base_spec.events,
        .structs = merged_structs,
        .enums = merged_enums,
    };
}

fn mergeMethods(
    arena: std.mem.Allocator,
    base: []const api.ApiMethod,
    discovered: []const api.ApiMethod,
) ![]const api.ApiMethod {
    var merged = std.ArrayList(api.ApiMethod).empty;
    for (base) |item| try merged.append(arena, item);

    for (discovered) |item| {
        var exists = false;
        for (merged.items) |existing| {
            if (!std.mem.eql(u8, existing.name, item.name)) continue;
            if (!eqlApiType(existing.input, item.input) or !eqlApiType(existing.output, item.output)) {
                return error.InvalidContract;
            }
            exists = true;
            break;
        }
        if (!exists) try merged.append(arena, item);
    }

    return merged.toOwnedSlice(arena);
}

fn mergeStructs(
    arena: std.mem.Allocator,
    base: []const api.UserStruct,
    discovered: []const api.UserStruct,
) ![]const api.UserStruct {
    var merged = std.ArrayList(api.UserStruct).empty;
    for (base) |item| try merged.append(arena, item);

    for (discovered) |item| {
        var exists = false;
        for (merged.items) |existing| {
            if (!std.mem.eql(u8, existing.name, item.name)) continue;
            if (!eqlStructDefinition(existing, item)) return error.InvalidContract;
            exists = true;
            break;
        }
        if (!exists) try merged.append(arena, item);
    }

    return merged.toOwnedSlice(arena);
}

fn mergeEnums(
    arena: std.mem.Allocator,
    base: []const api.UserEnum,
    discovered: []const api.UserEnum,
) ![]const api.UserEnum {
    var merged = std.ArrayList(api.UserEnum).empty;
    for (base) |item| try merged.append(arena, item);

    for (discovered) |item| {
        var exists = false;
        for (merged.items) |existing| {
            if (!std.mem.eql(u8, existing.name, item.name)) continue;
            if (!eqlEnumDefinition(existing, item)) return error.InvalidContract;
            exists = true;
            break;
        }
        if (!exists) try merged.append(arena, item);
    }

    return merged.toOwnedSlice(arena);
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

test {
    _ = @import("spec_tests.zig");
}
