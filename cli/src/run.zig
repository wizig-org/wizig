//! Shared run command entrypoint that forwards to unified runner.
const std = @import("std");
const Io = std.Io;

const unified = @import("run/unified.zig");

/// Top-level run command errors.
pub const RunError = error{RunFailed};

/// Executes unified run flow for project hosts/devices.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    return unified.run(arena, io, parent_environ_map, stderr, stdout, args);
}

/// Writes run command usage text.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Run:\n" ++
            "  wizig run [project_dir] [options]\n" ++
            "\n" ++
            "Project-level options:\n" ++
            "  --device <id_or_name>       Select target without prompt\n" ++
            "  --debugger <mode>           Pass through to selected platform\n" ++
            "  --non-interactive           Fail instead of prompting for selection\n" ++
            "  --once                      Launch and return without log/debug loop\n" ++
            "  --monitor-timeout <seconds> Stop log/console monitor automatically after timeout\n" ++
            "  --regenerate-host           Regenerate iOS xcodegen hosts from project.yml before run\n" ++
            "\n" ++
            "Project-level behavior:\n" ++
            "  - Detects generated app hosts under <project_dir>/ios and <project_dir>/android\n" ++
            "  - Shows a unified target list of available devices\n" ++
            "  - Runs the matching platform host automatically based on selected device\n" ++
            "\n",
    );
    try unified.printUsage(writer);
}

test {
    std.testing.refAllDecls(@import("run/unified.zig"));
}
