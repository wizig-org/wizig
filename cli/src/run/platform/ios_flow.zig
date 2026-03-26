//! iOS platform run orchestration.
//!
//! This module owns the public `wizig run ios` entrypoint and delegates target
//! discovery plus simulator/device launch details to smaller internal modules.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const config_parse = @import("config_parse.zig");
const ios_launch = @import("ios_launch.zig");
const options_mod = @import("options.zig");
const types = @import("types.zig");

const context = @import("ios_flow/context.zig");
const device_flow = @import("ios_flow/device.zig");
const selection = @import("ios_flow/selection.zig");
const simulator_flow = @import("ios_flow/simulator.zig");

/// Executes the full iOS run pipeline.
pub fn runIos(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !void {
    if (builtin.os.tag != .macos) {
        try stderr.writeAll("error: iOS run is only supported on macOS hosts\n");
        return error.RunFailed;
    }

    const debugger_mode = try options_mod.resolveIosDebugger(stderr, options.debugger);

    if (options.regenerate_host) {
        try ios_launch.maybeRegenerateIosProject(arena, io, stderr, stdout, options.project_dir);
    }

    const xcode_project = try ios_launch.findXcodeProject(arena, io, stderr, options.project_dir);
    const scheme = options.scheme orelse config_parse.inferSchemeFromProject(xcode_project) orelse {
        try stderr.writeAll("error: failed to infer iOS scheme, pass --scheme\n");
        return error.RunFailed;
    };

    const run_context: context.RunContext = .{
        .arena = arena,
        .io = io,
        .parent_environ_map = parent_environ_map,
        .stderr = stderr,
        .stdout = stdout,
        .options = options,
        .xcode_project = xcode_project,
        .scheme = scheme,
        .debugger_mode = debugger_mode,
    };

    const selected = try selection.resolveSelectedDevice(&run_context);

    const kind_label: []const u8 = switch (selected.kind) {
        .simulator => "simulator",
        .device => "device",
    };
    try stdout.print("selected iOS {s}: {s} [{s}] ({s}, {s})\n", .{ kind_label, selected.name, selected.udid, selected.runtime, selected.state });
    try stdout.flush();

    switch (selected.kind) {
        .simulator => try simulator_flow.run(&run_context, selected),
        .device => try device_flow.run(&run_context, selected),
    }
}
