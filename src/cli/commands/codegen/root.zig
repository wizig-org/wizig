//! `wizig codegen` command orchestration and public wrappers.
const std = @import("std");
const Io = std.Io;

const lock_enforce = @import("../../support/toolchains/lock_enforce.zig");
const options = @import("options.zig");
const targets = @import("targets.zig");
const watch_runner = @import("watch/runner.zig");
const contract_source = @import("contract/source.zig");
const contract_resolve = @import("contract/resolve.zig");
const generate_project = @import("root/generate_project.zig");
const path_util = @import("../../support/path.zig");

pub const ApiContractSource = contract_source.ApiContractSource;
pub const ResolvedApiContract = contract_source.ResolvedApiContract;

/// Parses codegen CLI options and triggers project generation.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed = try options.parseCodegenOptions(arena, stderr, args);
    if (parsed == null) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }
    const parsed_options = parsed.?;
    const root_abs = try path_util.resolveAbsolute(arena, io, parsed_options.project_root);

    try lock_enforce.enforceProjectLock(
        arena,
        io,
        stderr,
        root_abs,
        parsed_options.allow_toolchain_drift,
    );

    if (parsed_options.watch) {
        try watch_runner.runWatchCodegenLoop(
            io,
            stderr,
            stdout,
            root_abs,
            parsed_options.api_override,
            parsed_options.watch_interval_ms,
            resolveApiPathForWatch,
            generateProject,
        );
        return;
    }

    const contract = try resolveApiContract(arena, io, stderr, root_abs, parsed_options.api_override);
    try generateProject(
        arena,
        io,
        stderr,
        stdout,
        root_abs,
        if (contract) |resolved| resolved.path else null,
    );
}

/// Writes usage help for the codegen command.
pub fn printUsage(writer: *Io.Writer) !void {
    try options.printUsage(writer);
    const ts_supported = targets.supportedNow(.typescript);
    try writer.print("  Reserved target: typescript ({s})\n", .{if (ts_supported) "enabled" else "planned"});
}

/// Resolves API contract path from explicit override or project defaults.
pub fn resolveApiContract(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) !?ResolvedApiContract {
    return contract_resolve.resolveApiContract(arena, io, stderr, project_root, api_override);
}

/// Generates Zig/Swift/Kotlin API bindings from contract + `lib/**/*.zig` discovery.
pub fn generateProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) !void {
    return generate_project.generateProject(arena, io, stderr, stdout, project_root, api_path);
}

fn resolveApiPathForWatch(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) !?[]const u8 {
    const contract = try resolveApiContract(arena, io, stderr, project_root, api_override);
    return if (contract) |resolved| resolved.path else null;
}

test {
    _ = @import("root/reporting.zig");
    _ = @import("render/tests.zig");
}
