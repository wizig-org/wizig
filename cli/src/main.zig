//! Ziggy CLI entrypoint and command router.
const std = @import("std");
const Io = std.Io;

const create_cmd = @import("commands/create/root.zig");
const run_cmd = @import("commands/run/root.zig");
const plugin_cmd = @import("commands/plugin/root.zig");
const codegen_cmd = @import("commands/codegen/root.zig");
const doctor_cmd = @import("commands/doctor/root.zig");

/// Parses top-level CLI arguments and dispatches to command handlers.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [2048]u8 = undefined;
    var stderr_buffer: [2048]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);

    const stdout = &stdout_file_writer.interface;
    const stderr = &stderr_file_writer.interface;

    if (args.len < 2) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    const command = args[1];
    const rest = args[2..];

    if (std.mem.eql(u8, command, "create")) {
        create_cmd.run(arena, io, init.environ_map, stderr, stdout, rest) catch {
            std.process.exit(1);
        };
        return;
    }

    if (std.mem.eql(u8, command, "run")) {
        run_cmd.run(arena, io, init.environ_map, stderr, stdout, rest) catch {
            std.process.exit(1);
        };
        return;
    }

    if (std.mem.eql(u8, command, "plugin")) {
        plugin_cmd.run(arena, io, stderr, stdout, rest) catch {
            std.process.exit(1);
        };
        return;
    }

    if (std.mem.eql(u8, command, "codegen")) {
        codegen_cmd.run(arena, io, stderr, stdout, rest) catch {
            std.process.exit(1);
        };
        return;
    }

    if (std.mem.eql(u8, command, "doctor")) {
        doctor_cmd.run(arena, io, init.environ_map, stderr, stdout, rest) catch {
            std.process.exit(1);
        };
        return;
    }

    try stderr.writeAll("error: unknown command\n\n");
    try printUsage(stderr);
    try stderr.flush();
    std.process.exit(1);
}

fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Ziggy CLI\n\n" ++
            "Usage:\n" ++
            "  ziggy create <name> [destination_dir] [--platforms ios,android,macos] [--sdk-root <path>]\n" ++
            "  ziggy run [project_dir] [options]\n" ++
            "  ziggy plugin validate|sync|add ...\n" ++
            "  ziggy codegen [project_root] [--api <path>]\n" ++
            "  ziggy doctor [--sdk-root <path>]\n\n",
    );

    try create_cmd.printUsage(writer);
    try run_cmd.printUsage(writer);
    try plugin_cmd.printUsage(writer);
    try codegen_cmd.printUsage(writer);
    try doctor_cmd.printUsage(writer);
}

test "printUsage includes core commands" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    const output = out_writer.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy create") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy plugin") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy codegen") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy doctor") != null);
}
