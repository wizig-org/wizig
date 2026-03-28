//! Platform-specific run pipeline (`ios` / `android`).
//!
//! This module is the orchestrator entrypoint used by unified run mode.
//! It delegates option parsing, codegen preflight, and platform execution to
//! focused modules to keep behavior maintainable and testable.
const std = @import("std");
const Io = std.Io;

const android_flow = @import("android_flow.zig");
const codegen_preflight = @import("codegen_preflight.zig");
const ios_flow = @import("ios_flow.zig");
const options_mod = @import("options.zig");
const options_runtime = @import("options_runtime.zig");
const process = @import("process_supervisor.zig");

pub const types = @import("types.zig");

/// Executes platform run pipeline (`ios` or `android`) with parsed options.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed_options = try options_mod.parseRunOptions(arena, stderr, args);
    if (parsed_options == null) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }
    const options = try options_runtime.normalizeRunOptions(arena, io, parsed_options.?);
    return runWithOptions(arena, io, parent_environ_map, stderr, stdout, options);
}

/// Executes platform run pipeline for already-normalized options.
///
/// Unified run uses this typed entrypoint to avoid hidden string flag
/// protocols between orchestration layers.
pub fn runWithOptions(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !void {
    try maybeBuildCurrentWorkspace(arena, io, stderr, stdout, options.project_dir);

    if (!options.skip_codegen) {
        try codegen_preflight.runCodegenPreflight(arena, io, stderr, stdout, options.project_dir);
    }

    switch (options.platform) {
        .ios => try ios_flow.runIos(arena, io, parent_environ_map, stderr, stdout, options),
        .android => try android_flow.runAndroid(arena, io, parent_environ_map, stderr, stdout, options),
    }
}

/// Writes platform run usage help.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Run:\n" ++
            "  wizig run ios <project_dir> [options]\n" ++
            "  wizig run android <project_dir> [options]\n" ++
            "\n" ++
            "Shared options:\n" ++
            "  --device <id_or_name>       Select target without prompt (Android AVD: avd:<name>)\n" ++
            "  --debugger <auto|lldb|jdb|logcat|none>\n" ++
            "  --non-interactive           Fail instead of prompting for selection\n" ++
            "  --once                      Launch and exit without attaching/streaming\n" ++
            "  --monitor-timeout <seconds> Stop log/console monitor automatically after timeout\n" ++
            "  --regenerate-host           Regenerate iOS xcodegen hosts from project.yml before run\n" ++
            "\n" ++
            "iOS options:\n" ++
            "  --scheme <scheme>\n" ++
            "  --bundle-id <bundle_identifier>\n" ++
            "\n" ++
            "Android options:\n" ++
            "  --module <gradle_module>    Defaults to app\n" ++
            "  --app-id <application_id>\n" ++
            "  --activity <activity_or_component>\n",
    );
}

fn pathExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

/// Builds the current workspace only when it is the selected project root.
fn maybeBuildCurrentWorkspace(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_dir: []const u8,
) !void {
    if (!pathExists(io, "build.zig")) {
        try stdout.writeAll("note: build.zig not found in current directory; skipping zig build\n");
        try stdout.flush();
        return;
    }

    const cwd = try std.process.currentPathAlloc(io, arena);
    if (!shouldBuildWorkspaceForPaths(cwd, project_dir)) {
        try stdout.writeAll("note: current workspace differs from selected project; skipping ambient zig build\n");
        try stdout.flush();
        return;
    }

    try stdout.writeAll("building Zig artifacts...\n");
    try stdout.flush();
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "zig", "build" },
        .label = "build Zig artifacts",
    });
}

/// Returns whether the current workspace should be prebuilt for the run target.
fn shouldBuildWorkspaceForPaths(cwd_path: []const u8, project_dir: []const u8) bool {
    return std.mem.eql(u8, cwd_path, project_dir);
}

test {
    std.testing.refAllDecls(@import("options.zig"));
    std.testing.refAllDecls(@import("ios_discovery.zig"));
    std.testing.refAllDecls(@import("android_discovery.zig"));
}

test "shouldBuildWorkspaceForPaths only allows the selected project root" {
    try std.testing.expect(shouldBuildWorkspaceForPaths("/tmp/app", "/tmp/app"));
    try std.testing.expect(!shouldBuildWorkspaceForPaths("/tmp/wizig-repo", "/tmp/app"));
}
