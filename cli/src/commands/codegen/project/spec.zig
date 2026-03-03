//! Project-level API spec defaults and merge behavior.

const std = @import("std");
const api = @import("../model/api.zig");

pub fn defaultApiSpecForProject(arena: std.mem.Allocator, project_root: []const u8) !api.ApiSpec {
    const tail = std.fs.path.basename(project_root);
    const candidate = if (tail.len > 0) tail else "app";
    const namespace = try std.fmt.allocPrint(arena, "dev.wizig.{s}", .{candidate});
    const empty_methods = try arena.alloc(api.ApiMethod, 0);
    const empty_events = try arena.alloc(api.ApiEvent, 0);
    return .{
        .namespace = namespace,
        .methods = empty_methods,
        .events = empty_events,
    };
}

pub fn mergeSpecWithDiscoveredMethods(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered: []const api.ApiMethod,
) !api.ApiSpec {
    var merged = std.ArrayList(api.ApiMethod).empty;
    errdefer merged.deinit(arena);

    for (base_spec.methods) |method| {
        try merged.append(arena, method);
    }

    for (discovered) |method| {
        var exists = false;
        for (merged.items) |existing| {
            if (!std.mem.eql(u8, existing.name, method.name)) continue;
            if (existing.input != method.input or existing.output != method.output) {
                return error.InvalidContract;
            }
            exists = true;
            break;
        }
        if (!exists) try merged.append(arena, method);
    }

    return .{
        .namespace = base_spec.namespace,
        .methods = try merged.toOwnedSlice(arena),
        .events = base_spec.events,
    };
}
