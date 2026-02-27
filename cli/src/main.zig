const std = @import("std");
const Io = std.Io;
const ziggy_core = @import("ziggy_core");
const create_cmd = @import("create.zig");

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

    if (std.mem.eql(u8, args[1], "create")) {
        if (args.len < 4) {
            try stderr.writeAll("error: create expects <ios|android> <name> [destination_dir]\n");
            try stderr.flush();
            std.process.exit(1);
        }

        const platform = args[2];
        const app_name = args[3];
        const destination_dir = if (args.len >= 5) args[4] else app_name;

        if (std.mem.eql(u8, platform, "ios")) {
            create_cmd.createIos(arena, io, init.environ_map, stderr, stdout, app_name, destination_dir) catch {
                std.process.exit(1);
            };
            return;
        }

        if (std.mem.eql(u8, platform, "android")) {
            create_cmd.createAndroid(arena, io, init.environ_map, stderr, stdout, app_name, destination_dir) catch {
                std.process.exit(1);
            };
            return;
        }

        try stderr.print("error: unknown platform '{s}', expected ios or android\n", .{platform});
        try stderr.flush();
        std.process.exit(1);
    }

    if (std.mem.eql(u8, args[1], "plugin")) {
        if (args.len == 4 and std.mem.eql(u8, args[2], "validate")) {
            try pluginValidate(arena, io, stderr, stdout, args[3]);
            return;
        }

        if (args.len >= 3 and std.mem.eql(u8, args[2], "sync")) {
            const plugin_root = switch (args.len) {
                4, 5, 6, 7 => args[3],
                else => {
                    try stderr.writeAll(
                        "error: plugin sync expects <plugin_root> [registry_dir] [ios_dir] [android_dir]\n",
                    );
                    try stderr.flush();
                    std.process.exit(1);
                },
            };
            const registry_dir = if (args.len >= 5) args[4] else "plugins/registry";
            const ios_dir = if (args.len >= 6) args[5] else "sdk/ios/Sources/Ziggy";
            const android_dir = if (args.len >= 7) args[6] else "sdk/android/src/main/kotlin/dev/ziggy";
            try pluginSync(arena, io, stderr, stdout, plugin_root, registry_dir, ios_dir, android_dir);
            return;
        }
    }

    try stderr.writeAll("error: unknown command\n\n");
    try printUsage(stderr);
    try stderr.flush();
    std.process.exit(1);
}

fn pluginValidate(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    file_path: []const u8,
) !void {
    const manifest_text = std.Io.Dir.cwd().readFileAlloc(io, file_path, arena, .limited(1024 * 1024)) catch |err| {
        try stderr.print("error: failed to read '{s}': {s}\n", .{ file_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };

    var manifest = ziggy_core.PluginManifest.parse(arena, manifest_text) catch |err| {
        try stderr.print("error: invalid plugin manifest '{s}': {s}\n", .{ file_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
    defer manifest.deinit(arena);

    try stdout.print(
        "valid plugin '{s}' version {s} (api {d}) with {d} capabilities\n",
        .{ manifest.id, manifest.version, manifest.api_version, manifest.capabilities.len },
    );
    try stdout.flush();
}

fn pluginSync(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    plugin_root: []const u8,
    registry_dir: []const u8,
    ios_dir: []const u8,
    android_dir: []const u8,
) !void {
    var registry = ziggy_core.collectPluginRegistry(arena, io, plugin_root) catch |err| {
        try stderr.print("error: failed to collect plugins from '{s}': {s}\n", .{ plugin_root, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
    defer registry.deinit(arena);

    const lockfile = ziggy_core.renderPluginLockfile(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render lockfile: {s}\n", .{@errorName(err)});
        try stderr.flush();
        std.process.exit(1);
    };
    const zig_registrant = ziggy_core.renderZigRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Zig registrant: {s}\n", .{@errorName(err)});
        try stderr.flush();
        std.process.exit(1);
    };
    const swift_registrant = ziggy_core.renderSwiftRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Swift registrant: {s}\n", .{@errorName(err)});
        try stderr.flush();
        std.process.exit(1);
    };
    const kotlin_registrant = ziggy_core.renderKotlinRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Kotlin registrant: {s}\n", .{@errorName(err)});
        try stderr.flush();
        std.process.exit(1);
    };

    const lockfile_path = try joinPath(arena, registry_dir, "plugins.lock.toml");
    const zig_path = try joinPath(arena, registry_dir, "generated_plugins.zig");
    const swift_path = try joinPath(arena, ios_dir, "GeneratedPluginRegistrant.swift");
    const kotlin_path = try joinPath(arena, android_dir, "GeneratedPluginRegistrant.kt");

    writeFileAtomically(io, lockfile_path, lockfile) catch |err| {
        try stderr.print("error: failed to write '{s}': {s}\n", .{ lockfile_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
    writeFileAtomically(io, zig_path, zig_registrant) catch |err| {
        try stderr.print("error: failed to write '{s}': {s}\n", .{ zig_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
    writeFileAtomically(io, swift_path, swift_registrant) catch |err| {
        try stderr.print("error: failed to write '{s}': {s}\n", .{ swift_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
    writeFileAtomically(io, kotlin_path, kotlin_registrant) catch |err| {
        try stderr.print("error: failed to write '{s}': {s}\n", .{ kotlin_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };

    try stdout.print(
        "generated {d} plugins\n- {s}\n- {s}\n- {s}\n- {s}\n",
        .{
            registry.records.len,
            lockfile_path,
            zig_path,
            swift_path,
            kotlin_path,
        },
    );
    try stdout.flush();
}

fn writeFileAtomically(io: std.Io, path: []const u8, contents: []const u8) !void {
    var atomic_file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .make_path = true,
        .replace = true,
    });
    defer atomic_file.deinit(io);

    try atomic_file.file.writeStreamingAll(io, contents);
    try atomic_file.replace(io);
}

fn joinPath(allocator: std.mem.Allocator, base: []const u8, name: []const u8) ![]u8 {
    if (std.mem.eql(u8, base, ".")) {
        return allocator.dupe(u8, name);
    }
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ base, std.fs.path.sep_str, name });
}

fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Ziggy CLI\n" ++
            "\n" ++
            "Usage:\n" ++
            "  ziggy create ios <name> [destination_dir]\n" ++
            "  ziggy create android <name> [destination_dir]\n" ++
            "  ziggy plugin validate <ziggy-plugin.toml>\n" ++
            "  ziggy plugin sync <plugin_root> [registry_dir] [ios_dir] [android_dir]\n",
    );
}
