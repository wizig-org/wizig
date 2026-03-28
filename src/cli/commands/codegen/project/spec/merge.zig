//! API spec merge helpers.
const std = @import("std");

const api = @import("../../model/api.zig");
const equality = @import("equality.zig");

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
/// Conflicts are rejected when a discovered symbol reuses a name with a
/// different type signature or field/variant layout.
pub fn mergeSpecWithDiscoveredTypes(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered_methods: []const api.ApiMethod,
    discovered_structs: []const api.UserStruct,
    discovered_enums: []const api.UserEnum,
) !api.ApiSpec {
    return .{
        .namespace = base_spec.namespace,
        .methods = try mergeMethods(arena, base_spec.methods, discovered_methods),
        .events = base_spec.events,
        .structs = try mergeStructs(arena, base_spec.structs, discovered_structs),
        .enums = try mergeEnums(arena, base_spec.enums, discovered_enums),
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
            if (!equality.apiTypesEqual(existing.input, item.input) or !equality.apiTypesEqual(existing.output, item.output)) {
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
            if (!equality.structsEqual(existing, item)) return error.InvalidContract;
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
            if (!equality.enumsEqual(existing, item)) return error.InvalidContract;
            exists = true;
            break;
        }
        if (!exists) try merged.append(arena, item);
    }

    return merged.toOwnedSlice(arena);
}

test "mergeSpecWithDiscoveredTypes merges discovered methods and types" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const base_spec: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{},
        .enums = &.{},
    };
    const discovered_methods = [_]api.ApiMethod{
        .{ .name = "favorite_color", .input = .void, .output = .{ .user_enum = "Color" } },
    };
    const discovered_structs = [_]api.UserStruct{
        .{ .name = "UserProfile", .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "favorite", .field_type = .{ .user_enum = "Color" } },
        } },
    };
    const discovered_enums = [_]api.UserEnum{
        .{ .name = "Color", .variants = &.{ "red", "green" } },
    };

    const merged = try mergeSpecWithDiscoveredTypes(
        arena,
        base_spec,
        &discovered_methods,
        &discovered_structs,
        &discovered_enums,
    );

    try std.testing.expectEqual(@as(usize, 1), merged.methods.len);
    try std.testing.expectEqual(@as(usize, 1), merged.structs.len);
    try std.testing.expectEqual(@as(usize, 1), merged.enums.len);
}

test "mergeMethods rejects conflicting signatures" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const base_spec: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "ping", .input = .void, .output = .void }},
        .events = &.{},
        .structs = &.{},
        .enums = &.{},
    };
    const discovered_methods = [_]api.ApiMethod{
        .{ .name = "ping", .input = .int, .output = .void },
    };

    try std.testing.expectError(
        error.InvalidContract,
        mergeSpecWithDiscoveredMethods(arena, base_spec, &discovered_methods),
    );
}

test "mergeStructs rejects conflicting field layouts" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const base_spec: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{.{ .name = "UserProfile", .fields = &.{
            .{ .name = "name", .field_type = .string },
        } }},
        .enums = &.{},
    };
    const discovered_structs = [_]api.UserStruct{
        .{ .name = "UserProfile", .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "age", .field_type = .int },
        } },
    };

    try std.testing.expectError(
        error.InvalidContract,
        mergeSpecWithDiscoveredTypes(arena, base_spec, &.{}, &discovered_structs, &.{}),
    );
}

test "mergeEnums rejects conflicting variants" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const base_spec: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{},
        .enums = &.{.{ .name = "Color", .variants = &.{ "red", "green" } }},
    };
    const discovered_enums = [_]api.UserEnum{
        .{ .name = "Color", .variants = &.{ "red", "blue" } },
    };

    try std.testing.expectError(
        error.InvalidContract,
        mergeSpecWithDiscoveredTypes(arena, base_spec, &.{}, &.{}, &discovered_enums),
    );
}
