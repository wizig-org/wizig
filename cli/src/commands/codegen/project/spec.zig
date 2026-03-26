//! Project-level API spec facade.
//!
//! This module keeps the public codegen API stable while delegating default
//! spec creation and merge logic to smaller focused helpers.

const std = @import("std");

const api = @import("../model/api.zig");
const defaults = @import("spec/defaults.zig");
const merge = @import("spec/merge.zig");

/// Builds a minimal default API spec for projects with no explicit contract.
pub fn defaultApiSpecForProject(arena: std.mem.Allocator, project_root: []const u8) !api.ApiSpec {
    return defaults.defaultApiSpecForProject(arena, project_root);
}

/// Legacy merge entry-point kept for existing call sites.
pub fn mergeSpecWithDiscoveredMethods(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered_methods: []const api.ApiMethod,
) !api.ApiSpec {
    return merge.mergeSpecWithDiscoveredMethods(arena, base_spec, discovered_methods);
}

/// Merges discovered methods and user-defined types into a base spec.
pub fn mergeSpecWithDiscoveredTypes(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered_methods: []const api.ApiMethod,
    discovered_structs: []const api.UserStruct,
    discovered_enums: []const api.UserEnum,
) !api.ApiSpec {
    return merge.mergeSpecWithDiscoveredTypes(
        arena,
        base_spec,
        discovered_methods,
        discovered_structs,
        discovered_enums,
    );
}

test {
    _ = @import("spec_tests.zig");
}
