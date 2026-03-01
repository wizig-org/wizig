//! Code generation preflight for platform run commands.
//!
//! The platform runner reuses codegen logic so host-side bindings remain in
//! sync with current app sources before build/install operations.
const std = @import("std");
const Io = std.Io;

const codegen_cmd = @import("../../commands/codegen/root.zig");

/// Ensures app bindings are generated before platform build execution.
pub fn runCodegenPreflight(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    host_project_dir: []const u8,
) !void {
    const app_root = std.fs.path.dirname(host_project_dir) orelse host_project_dir;
    const contract = try codegen_cmd.resolveApiContract(arena, io, stderr, app_root, null);
    codegen_cmd.generateProject(arena, io, stderr, stdout, app_root, if (contract) |resolved| resolved.path else null) catch |err| {
        if (contract) |resolved| {
            try stderr.print("error: failed to generate API bindings from '{s}': {s}\n", .{ resolved.path, @errorName(err) });
        } else {
            try stderr.print("error: failed to generate API bindings from discovered lib methods: {s}\n", .{@errorName(err)});
        }
        try stderr.flush();
        return error.RunFailed;
    };
}
