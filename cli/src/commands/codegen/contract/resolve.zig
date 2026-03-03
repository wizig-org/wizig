//! Contract path resolution from CLI override or project defaults.

const std = @import("std");
const Io = std.Io;
const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const source = @import("source.zig");

pub fn resolveApiContract(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) !?source.ResolvedApiContract {
    if (api_override) |raw| {
        const path = try path_util.resolveAbsolute(arena, io, raw);
        if (!fs_util.pathExists(io, path)) {
            try stderr.print("error: API contract does not exist: {s}\n", .{path});
            return error.InvalidArguments;
        }

        const contract_source = source.apiSourceFromPath(path) catch {
            try stderr.print("error: unsupported API contract extension: {s}\n", .{path});
            try stderr.writeAll("hint: use `.zig` or `.json`\n");
            return error.InvalidArguments;
        };

        return .{
            .path = path,
            .source = contract_source,
        };
    }

    const zig_path = try path_util.join(arena, project_root, "wizig.api.zig");
    if (fs_util.pathExists(io, zig_path)) {
        return .{ .path = zig_path, .source = .zig };
    }

    const json_path = try path_util.join(arena, project_root, "wizig.api.json");
    if (fs_util.pathExists(io, json_path)) {
        return .{ .path = json_path, .source = .json };
    }

    return null;
}
