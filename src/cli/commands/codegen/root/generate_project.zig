//! High-level orchestration for one complete codegen pass.
const std = @import("std");
const Io = std.Io;

const host_sync = @import("host_sync.zig");
const output_plan = @import("output_plan.zig");
const output_write = @import("output_write.zig");
const reporting = @import("reporting.zig");
const spec_bundle = @import("spec_bundle.zig");

/// Generates project bindings, synchronizes host artifacts, and prints the summary.
pub fn generateProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) !void {
    const bundle = try spec_bundle.build(arena, io, stderr, project_root, api_path);
    const plan = try output_plan.prepare(arena, io, project_root);
    const write_result = try output_write.renderAndWrite(arena, io, stderr, project_root, plan, bundle);
    const sync_result = try host_sync.syncHosts(arena, io, stderr, project_root, bundle.spec);
    try reporting.writeGenerationReport(stdout, bundle.maybe_source, plan, write_result, sync_result);
}
