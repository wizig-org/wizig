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
    const parsed_options = options_mod.parseRunOptions(args, stderr) catch {
        try printUsage(stderr);
        try stderr.flush();
        return error.RunFailed;
    };
    const options = try options_mod.normalizeRunOptions(arena, io, parsed_options);

    if (pathExists(io, "build.zig")) {
        try stdout.writeAll("building Zig artifacts...\n");
        try stdout.flush();
        try process.runInheritChecked(io, stderr, .{
            .argv = &.{ "zig", "build" },
            .label = "build Zig artifacts",
        });
    } else {
        try stdout.writeAll("note: build.zig not found in current directory; skipping zig build\n");
        try stdout.flush();
    }

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

test {
    std.testing.refAllDecls(@import("options.zig"));
    std.testing.refAllDecls(@import("ios_discovery.zig"));
    std.testing.refAllDecls(@import("android_discovery.zig"));
}
