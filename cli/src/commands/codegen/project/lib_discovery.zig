//! Discovery of API method signatures and module imports from `lib/**/*.zig`.
const std = @import("std");

const api = @import("../model/api.zig");
const files = @import("lib_discovery/files.zig");
const signature = @import("lib_discovery/signature.zig");

/// Discovers public API methods from `lib/**/*.zig` using only built-in type rules.
pub fn discoverLibApiMethods(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const api.ApiMethod {
    return discoverLibApiMethodsWithTypes(arena, io, project_root, &.{}, &.{});
}

/// Discovers public API methods from `lib/**/*.zig`, resolving known struct and enum names.
pub fn discoverLibApiMethodsWithTypes(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiMethod {
    return signature.discoverLibApiMethodsWithTypes(
        arena,
        io,
        project_root,
        known_struct_names,
        known_enum_names,
    );
}

/// Collects import paths for `lib/**/*.zig` files.
pub fn collectLibModuleImports(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
    return files.collectLibModuleImports(arena, io, project_root);
}

test {
    _ = @import("lib_discovery/files.zig");
    _ = @import("lib_discovery/signature.zig");
}
