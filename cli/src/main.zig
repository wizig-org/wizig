const std = @import("std");
const Io = std.Io;
const ziggy_core = @import("ziggy_core");
const create_cmd = @import("create.zig");
const run_cmd = @import("run.zig");

const CreateMode = enum {
    app,
    ios,
    android,
};

const CreateRequest = struct {
    mode: CreateMode,
    app_name: []const u8,
    destination_dir: []const u8,
    platforms: create_cmd.CreatePlatforms = .{},
};

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
        const request = parseCreateRequest(args[2..], stderr) catch {
            try stderr.flush();
            std.process.exit(1);
        };

        switch (request.mode) {
            .app => create_cmd.createApp(
                arena,
                io,
                init.environ_map,
                stderr,
                stdout,
                request.app_name,
                request.destination_dir,
                request.platforms,
            ) catch {
                std.process.exit(1);
            },
            .ios => create_cmd.createIos(arena, io, init.environ_map, stderr, stdout, request.app_name, request.destination_dir) catch {
                std.process.exit(1);
            },
            .android => create_cmd.createAndroid(arena, io, init.environ_map, stderr, stdout, request.app_name, request.destination_dir) catch {
                std.process.exit(1);
            },
        }
        return;
    }

    if (std.mem.eql(u8, args[1], "run")) {
        run_cmd.run(arena, io, init.environ_map, stderr, stdout, args[2..]) catch {
            std.process.exit(1);
        };
        return;
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

fn parseCreateRequest(args: []const []const u8, stderr: *Io.Writer) !CreateRequest {
    if (args.len == 0) {
        try stderr.writeAll("error: create expects <name> [destination_dir] [--platforms ios,android,macos]\n");
        return error.InvalidArguments;
    }

    const first = args[0];
    if (std.mem.eql(u8, first, "ios") or std.mem.eql(u8, first, "android")) {
        if (args.len < 2 or args.len > 3) {
            try stderr.writeAll("error: create expects <ios|android> <name> [destination_dir]\n");
            return error.InvalidArguments;
        }

        if (args.len == 3 and isOptionArg(args[2])) {
            try stderr.print("error: unexpected option '{s}' for legacy platform create\n", .{args[2]});
            return error.InvalidArguments;
        }

        return .{
            .mode = if (std.mem.eql(u8, first, "ios")) .ios else .android,
            .app_name = args[1],
            .destination_dir = if (args.len == 3) args[2] else args[1],
        };
    }

    var index: usize = 0;
    if (std.mem.eql(u8, first, "app")) {
        index = 1;
    }
    if (index >= args.len) {
        try stderr.writeAll("error: create expects <name> [destination_dir] [--platforms ios,android,macos]\n");
        return error.InvalidArguments;
    }

    const app_name = args[index];
    index += 1;
    var destination_dir = app_name;
    if (index < args.len and !isOptionArg(args[index])) {
        destination_dir = args[index];
        index += 1;
    }

    var platforms = create_cmd.CreatePlatforms{};
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--platforms")) {
            if (index + 1 >= args.len) {
                try stderr.writeAll("error: missing value for --platforms\n");
                return error.InvalidArguments;
            }
            platforms = try parseCreatePlatforms(args[index + 1], stderr);
            index += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--platforms=")) {
            platforms = try parseCreatePlatforms(arg["--platforms=".len..], stderr);
            index += 1;
            continue;
        }

        try stderr.print("error: unknown create option '{s}'\n", .{arg});
        return error.InvalidArguments;
    }

    if (!hasAnyCreatePlatform(platforms)) {
        try stderr.writeAll("error: at least one platform must be selected\n");
        return error.InvalidArguments;
    }

    return .{
        .mode = .app,
        .app_name = app_name,
        .destination_dir = destination_dir,
        .platforms = platforms,
    };
}

fn parseCreatePlatforms(raw: []const u8, stderr: *Io.Writer) !create_cmd.CreatePlatforms {
    var platforms = create_cmd.CreatePlatforms{
        .ios = false,
        .android = false,
        .macos = false,
    };

    var parts = std.mem.splitScalar(u8, raw, ',');
    while (parts.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t\r\n");
        if (part.len == 0) continue;

        if (std.mem.eql(u8, part, "ios")) {
            platforms.ios = true;
            continue;
        }
        if (std.mem.eql(u8, part, "android")) {
            platforms.android = true;
            continue;
        }
        if (std.mem.eql(u8, part, "macos")) {
            platforms.macos = true;
            continue;
        }
        if (std.mem.eql(u8, part, "mobile")) {
            platforms.ios = true;
            platforms.android = true;
            continue;
        }
        if (std.mem.eql(u8, part, "all")) {
            platforms.ios = true;
            platforms.android = true;
            platforms.macos = true;
            continue;
        }

        try stderr.print("error: unsupported platform '{s}' in --platforms\n", .{part});
        return error.InvalidArguments;
    }

    if (!hasAnyCreatePlatform(platforms)) {
        try stderr.writeAll("error: --platforms must include at least one platform\n");
        return error.InvalidArguments;
    }

    return platforms;
}

fn hasAnyCreatePlatform(platforms: create_cmd.CreatePlatforms) bool {
    return platforms.ios or platforms.android or platforms.macos;
}

fn isOptionArg(arg: []const u8) bool {
    return std.mem.startsWith(u8, arg, "--");
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
            "  ziggy create <name> [destination_dir] [--platforms ios,android,macos]\n" ++
            "  ziggy create app <name> [destination_dir] [--platforms ios,android,macos]\n" ++
            "  ziggy create ios <name> [destination_dir]\n" ++
            "  ziggy create android <name> [destination_dir]\n" ++
            "  ziggy run ios|android <project_dir> [options]\n" ++
            "  ziggy plugin validate <ziggy-plugin.toml>\n" ++
            "  ziggy plugin sync <plugin_root> [registry_dir] [ios_dir] [android_dir]\n" ++
            "\n",
    );
    try run_cmd.printUsage(writer);
}

test "printUsage includes key commands" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printUsage(&out_writer.writer);
    const output = out_writer.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy create <name>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy create ios") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy run ios|android") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ziggy plugin sync") != null);
}

test "parseCreateRequest defaults to mobile app scaffold" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const request = try parseCreateRequest(&.{"MyApp"}, &err_writer.writer);
    try std.testing.expectEqual(.app, request.mode);
    try std.testing.expectEqualStrings("MyApp", request.app_name);
    try std.testing.expectEqualStrings("MyApp", request.destination_dir);
    try std.testing.expect(request.platforms.ios);
    try std.testing.expect(request.platforms.android);
    try std.testing.expect(!request.platforms.macos);
}

test "parseCreateRequest accepts explicit platforms" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const request = try parseCreateRequest(
        &.{ "app", "MyApp", "workspace/MyApp", "--platforms=ios,macos" },
        &err_writer.writer,
    );
    try std.testing.expectEqual(.app, request.mode);
    try std.testing.expectEqualStrings("MyApp", request.app_name);
    try std.testing.expectEqualStrings("workspace/MyApp", request.destination_dir);
    try std.testing.expect(request.platforms.ios);
    try std.testing.expect(!request.platforms.android);
    try std.testing.expect(request.platforms.macos);
}

test "parseCreateRequest keeps legacy platform form" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const request = try parseCreateRequest(&.{ "android", "Demo", "examples/android/Demo" }, &err_writer.writer);
    try std.testing.expectEqual(.android, request.mode);
    try std.testing.expectEqualStrings("Demo", request.app_name);
    try std.testing.expectEqualStrings("examples/android/Demo", request.destination_dir);
}

test "pluginValidate accepts known manifest" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try pluginValidate(
        arena,
        std.testing.io,
        &err_writer.writer,
        &out_writer.writer,
        "examples/plugin-hello/ziggy-plugin.toml",
    );

    try std.testing.expect(std.mem.indexOf(u8, out_writer.writer.buffered(), "valid plugin 'dev.ziggy.hello'") != null);
}

test "pluginSync generates registrants for plugin tree" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const io = std.testing.io;
    const gpa = arena;

    const root_path = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root_path);

    try tmp.dir.createDirPath(io, "plugins/demo");
    try tmp.dir.writeFile(io, .{
        .sub_path = "plugins/demo/ziggy-plugin.toml",
        .data =
        \\id = "dev.ziggy.demo"
        \\version = "1.2.3"
        \\api_version = 1
        \\capabilities = ["log"]
        \\ios_spm = []
        \\android_maven = []
        \\
        ,
    });

    const plugin_root = try std.fmt.allocPrint(gpa, "{s}{s}plugins", .{ root_path, std.fs.path.sep_str });
    defer gpa.free(plugin_root);
    const registry_dir = try std.fmt.allocPrint(gpa, "{s}{s}registry", .{ root_path, std.fs.path.sep_str });
    defer gpa.free(registry_dir);
    const ios_dir = try std.fmt.allocPrint(gpa, "{s}{s}ios", .{ root_path, std.fs.path.sep_str });
    defer gpa.free(ios_dir);
    const android_dir = try std.fmt.allocPrint(gpa, "{s}{s}android", .{ root_path, std.fs.path.sep_str });
    defer gpa.free(android_dir);

    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try pluginSync(
        gpa,
        io,
        &err_writer.writer,
        &out_writer.writer,
        plugin_root,
        registry_dir,
        ios_dir,
        android_dir,
    );

    const lockfile_path = try std.fmt.allocPrint(gpa, "{s}{s}plugins.lock.toml", .{ registry_dir, std.fs.path.sep_str });
    defer gpa.free(lockfile_path);
    const lockfile = try std.Io.Dir.cwd().readFileAlloc(io, lockfile_path, gpa, .limited(1024 * 1024));
    defer gpa.free(lockfile);
    try std.testing.expect(std.mem.indexOf(u8, lockfile, "dev.ziggy.demo") != null);
}
