//! Wizig CLI entrypoint and command router.
const std = @import("std");
const Io = std.Io;

const build_options = @import("build_options");
const build_cmd = @import("commands/build/root.zig");
const create_cmd = @import("commands/create/root.zig");
const run_cmd = @import("commands/run/root.zig");
const plugin_cmd = @import("commands/plugin/root.zig");
const codegen_cmd = @import("commands/codegen/root.zig");
const doctor_cmd = @import("commands/doctor/root.zig");
const self_update_cmd = @import("commands/self_update.zig");
const uninstall_cmd = @import("commands/uninstall.zig");

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

    if (std.mem.eql(u8, command, "build")) {
        build_cmd.run(arena, io, stderr, stdout, rest) catch {
            std.process.exit(1);
        };
        return;
    }

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

    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version")) {
        try stdout.writeAll(build_options.version);
        try stdout.writeAll("\n");
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "self-update")) {
        self_update_cmd.run(arena, io, stderr, stdout) catch {
            std.process.exit(1);
        };
        return;
    }

    if (std.mem.eql(u8, command, "uninstall")) {
        uninstall_cmd.run(arena, io, stderr, stdout, rest) catch {
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
        "Wizig CLI\n\n" ++
            "Usage:\n" ++
            "  wizig build android --release [--abis arm64-v8a,armeabi-v7a,x86_64]\n" ++
            "  wizig create <name> [destination_dir] [--platforms ios,android,macos] [--sdk-root <path>]\n" ++
            "  wizig run [project_dir] [options] [--allow-toolchain-drift]\n" ++
            "  wizig plugin validate|sync|add ...\n" ++
            "  wizig codegen [project_root] [--api <path>] [--watch] [--watch-interval-ms <milliseconds>] [--allow-toolchain-drift]\n" ++
            "  wizig doctor [--sdk-root <path>]\n" ++
            "  wizig version\n" ++
            "  wizig self-update\n" ++
            "  wizig uninstall [--yes]\n\n",
    );

    try build_cmd.printUsage(writer);
    try create_cmd.printUsage(writer);
    try run_cmd.printUsage(writer);
    try plugin_cmd.printUsage(writer);
    try codegen_cmd.printUsage(writer);
    try doctor_cmd.printUsage(writer);
    try self_update_cmd.printUsage(writer);
    try uninstall_cmd.printUsage(writer);
}

test "printUsage includes core commands" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    const output = out_writer.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig create") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig plugin") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig codegen") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig version") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig self-update") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig uninstall") != null);
}
