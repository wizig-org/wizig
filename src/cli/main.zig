//! Wizig CLI entrypoint and command router.
const std = @import("std");
const Io = std.Io;

const build_options = @import("build_options");
const main_args = @import("main_args.zig");
const build_cmd = @import("commands/build/root.zig");
const create_cmd = @import("commands/create/root.zig");
const run_cmd = @import("commands/run/root.zig");
const plugin_cmd = @import("commands/plugin/root.zig");
const codegen_cmd = @import("commands/codegen/root.zig");
const doctor_cmd = @import("commands/doctor/root.zig");
const self_update_cmd = @import("commands/self_update.zig");
const uninstall_cmd = @import("commands/uninstall.zig");
const version_cmd = @import("commands/version.zig");

/// Parses top-level CLI arguments and dispatches to command handlers.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const cli_args = if (args.len > 0) args[1..] else &.{};
    const io = init.io;

    var stdout_buffer: [2048]u8 = undefined;
    var stderr_buffer: [2048]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);

    const stdout = &stdout_file_writer.interface;
    const stderr = &stderr_file_writer.interface;

    const parsed = main_args.parse(arena, stderr, cli_args) catch {
        std.process.exit(1);
    };

    if (parsed.help) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    if (parsed.version and parsed.command == null) {
        try version_cmd.printVersion(stdout);
        try stdout.flush();
        return;
    }

    if (parsed.command == null) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    if (parsed.version) {
        try version_cmd.printVersion(stdout);
        try stdout.flush();
        return;
    }

    if (parsed.command.? == .version) {
        if (isHelpRequest(parsed.remaining)) {
            try version_cmd.printUsage(stdout);
        } else {
            try version_cmd.printVersion(stdout);
        }
        try stdout.flush();
        return;
    }

    switch (parsed.command.?) {
        .build => build_cmd.run(arena, io, stderr, stdout, parsed.remaining) catch std.process.exit(1),
        .create => create_cmd.run(arena, io, init.environ_map, stderr, stdout, parsed.remaining) catch std.process.exit(1),
        .run => run_cmd.run(arena, io, init.environ_map, stderr, stdout, parsed.remaining) catch std.process.exit(1),
        .plugin => plugin_cmd.run(arena, io, stderr, stdout, parsed.remaining) catch std.process.exit(1),
        .codegen => codegen_cmd.run(arena, io, stderr, stdout, parsed.remaining) catch std.process.exit(1),
        .doctor => doctor_cmd.run(arena, io, init.environ_map, stderr, stdout, parsed.remaining) catch std.process.exit(1),
        .@"self-update" => self_update_cmd.run(arena, io, stderr, stdout, parsed.remaining) catch std.process.exit(1),
        .uninstall => uninstall_cmd.run(arena, io, stderr, stdout, parsed.remaining) catch std.process.exit(1),
        .version => unreachable,
    }
}

fn isHelpRequest(args: []const []const u8) bool {
    return args.len == 1 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help"));
}

fn printUsage(writer: *Io.Writer) !void {
    try main_args.printUsage(writer);
}

test "printUsage includes core commands" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    const output = out_writer.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "create") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Run `wizig <command> --help`") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Detailed Command Help") == null);
}
