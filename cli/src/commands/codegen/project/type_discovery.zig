//! User-type discovery from `lib/**/*.zig`.
//!
//! This facade keeps the public API stable while delegating filesystem walking
//! and registry assembly to smaller modules.

const std = @import("std");
const api = @import("../model/api.zig");
const parse = @import("type_discovery_parse.zig");
const registry = @import("type_discovery/registry.zig");

/// Collected user-defined type information discovered from app sources.
pub const TypeRegistry = registry.TypeRegistry;

/// Discovers user structs and enums from `project_root/lib/**/*.zig`.
pub fn discoverLibTypes(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !TypeRegistry {
    return registry.discoverLibTypes(arena, io, project_root);
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

test {
    _ = @import("type_discovery_tests.zig");
}
