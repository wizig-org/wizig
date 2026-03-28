//! Default API spec construction helpers.
const std = @import("std");

const api = @import("../../model/api.zig");

/// Builds a minimal default API spec for a project root path.
pub fn defaultApiSpecForProject(arena: std.mem.Allocator, project_root: []const u8) !api.ApiSpec {
    const namespace = try defaultNamespaceForProjectRoot(arena, project_root);
    return .{
        .namespace = namespace,
        .methods = &.{},
        .events = &.{},
        .structs = &.{},
        .enums = &.{},
    };
}

/// Returns the default API namespace suffix for a project root.
pub fn defaultNamespaceForProjectRoot(arena: std.mem.Allocator, project_root: []const u8) ![]const u8 {
    const tail = std.fs.path.basename(project_root);
    const candidate = if (tail.len > 0) tail else "app";
    return std.fmt.allocPrint(arena, "dev.wizig.{s}", .{candidate});
}

test "defaultNamespaceForProjectRoot uses the project folder name" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const namespace = try defaultNamespaceForProjectRoot(arena, "/tmp/example-app");
    try std.testing.expectEqualStrings("dev.wizig.example-app", namespace);
}

test "defaultApiSpecForProject uses app when root basename is empty" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const spec = try defaultApiSpecForProject(arena, "");
    try std.testing.expectEqualStrings("dev.wizig.app", spec.namespace);
}
