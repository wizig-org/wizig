//! `wizig codegen` command and typed API binding generators.
const std = @import("std");
const Io = std.Io;
const fs_util = @import("../../support/fs.zig");
const path_util = @import("../../support/path.zig");
const android_gradle_migration = @import("../../run/platform/android_gradle_migration.zig");
const compatibility = @import("compatibility.zig");
const ios_host_patch = @import("ios_host_patch.zig");
const options = @import("options.zig");
const targets = @import("targets.zig");
const watch_runner = @import("watch/runner.zig");

/// Supported contract source formats.
pub const ApiContractSource = enum {
    zig,
    json,
};

/// Resolved API contract file path and format.
pub const ResolvedApiContract = struct {
    path: []const u8,
    source: ApiContractSource,
};

/// Parses codegen CLI options and triggers project generation.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed = try options.parseCodegenOptions(args, stderr);
    const root_abs = try path_util.resolveAbsolute(arena, io, parsed.project_root);

    if (parsed.watch) {
        try watch_runner.runWatchCodegenLoop(
            io,
            stderr,
            stdout,
            root_abs,
            parsed.api_override,
            parsed.watch_interval_ms,
            resolveApiPathForWatch,
            generateProject,
        );
        return;
    }

    const contract = try resolveApiContract(arena, io, stderr, root_abs, parsed.api_override);
    try generateProject(arena, io, stderr, stdout, root_abs, if (contract) |resolved| resolved.path else null);
}

/// Writes usage help for the codegen command.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    const ts_supported = targets.supportedNow(.typescript);
    try writer.writeAll(
        "Codegen:\n" ++
            "  wizig codegen [project_root] [--api <path>] [--watch] [--watch-interval-ms <milliseconds>]\n" ++
            "  # default contract lookup: wizig.api.zig -> wizig.api.json (optional)\n" ++
            "  # watch mode: incremental codegen on lib/**/*.zig and contract changes\n" ++
            "  # current targets: zig, swift, kotlin\n",
    );
    try writer.print("  # default watch interval: {d}ms\n", .{options.default_watch_interval_ms});
    try writer.print("  # reserved target: typescript ({s})\n\n", .{if (ts_supported) "enabled" else "planned"});
}

/// Resolves contract path for the watch runner callback interface.
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

/// Resolves API contract path from explicit override or project defaults.
pub fn resolveApiContract(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) !?ResolvedApiContract {
    if (api_override) |raw| {
        const path = try path_util.resolveAbsolute(arena, io, raw);
        if (!fs_util.pathExists(io, path)) {
            try stderr.print("error: API contract does not exist: {s}\n", .{path});
            return error.InvalidArguments;
        }
        const source = apiSourceFromPath(path) catch {
            try stderr.print("error: unsupported API contract extension: {s}\n", .{path});
            try stderr.writeAll("hint: use `.zig` or `.json`\n");
            return error.InvalidArguments;
        };
        return .{ .path = path, .source = source };
    }

    const zig_path = try path_util.join(arena, project_root, "wizig.api.zig");
    if (fs_util.pathExists(io, zig_path)) {
        return .{ .path = zig_path, .source = .zig };
    }

    const json_path = try path_util.join(arena, project_root, "wizig.api.json");
    if (fs_util.pathExists(io, json_path)) {
        return .{ .path = json_path, .source = .json };
    }

    return null;
}

/// Generates Zig/Swift/Kotlin API bindings from optional contract + `lib/**/*.zig` discovery.
pub fn generateProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) !void {
    const maybe_source: ?ApiContractSource = if (api_path) |path| blk: {
        const source = apiSourceFromPath(path) catch {
            try stderr.print("error: unsupported API contract extension: {s}\n", .{path});
            try stderr.writeAll("hint: use `.zig` or `.json`\n");
            return error.CodegenFailed;
        };
        break :blk source;
    } else null;

    const base_spec = if (api_path) |path| blk: {
        const source = maybe_source.?;
        const text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1024 * 1024)) catch |err| {
            try stderr.print("error: failed to read API contract '{s}': {s}\n", .{ path, @errorName(err) });
            return error.CodegenFailed;
        };

        break :blk switch (source) {
            .json => parseApiSpecFromJson(arena, text),
            .zig => parseApiSpecFromZig(arena, text),
        } catch |err| {
            try stderr.print("error: invalid API contract '{s}': {s}\n", .{ path, @errorName(err) });
            return error.CodegenFailed;
        };
    } else try defaultApiSpecForProject(arena, project_root);

    const discovered_methods = try discoverLibApiMethods(arena, io, project_root);
    const spec = try mergeSpecWithDiscoveredMethods(arena, base_spec, discovered_methods);
    const compat = try compatibility.buildMetadata(arena, spec.namespace, spec.methods, spec.events);

    const generated_root = try path_util.join(arena, project_root, ".wizig/generated");
    const zig_dir = try path_util.join(arena, generated_root, "zig");
    const swift_dir = try path_util.join(arena, generated_root, "swift");
    const kotlin_dir = try path_util.join(arena, generated_root, "kotlin/dev/wizig");
    const android_jni_dir = try path_util.join(arena, generated_root, "android/jni");
    const app_module_imports = try collectLibModuleImports(arena, io, project_root);

    try fs_util.ensureDir(io, zig_dir);
    try fs_util.ensureDir(io, swift_dir);
    try fs_util.ensureDir(io, kotlin_dir);
    try fs_util.ensureDir(io, android_jni_dir);

    const zig_out = try renderZigApi(arena, spec);
    const zig_ffi_root_out = try renderZigFfiRoot(arena, spec, compat);
    const zig_app_module_out = try renderZigAppModule(arena, spec, app_module_imports);
    const swift_out = try renderSwiftApi(arena, spec, compat);
    const kotlin_out = try renderKotlinApi(arena, spec, compat);
    const android_jni_bridge_out = try renderAndroidJniBridge(arena, spec, compat);
    const android_jni_cmake_out = try renderAndroidJniCmake(arena);

    const zig_file = try path_util.join(arena, zig_dir, "WizigGeneratedApi.zig");
    const zig_ffi_root_file = try path_util.join(arena, zig_dir, "WizigGeneratedFfiRoot.zig");
    const zig_app_module_file = try path_util.join(arena, project_root, "lib/WizigGeneratedAppModule.zig");
    const swift_file = try path_util.join(arena, swift_dir, "WizigGeneratedApi.swift");
    const kotlin_file = try path_util.join(arena, kotlin_dir, "WizigGeneratedApi.kt");
    const android_jni_bridge_file = try path_util.join(arena, android_jni_dir, "WizigGeneratedApiBridge.c");
    const android_jni_cmake_file = try path_util.join(arena, android_jni_dir, "CMakeLists.txt");
    const ios_mirror_swift_file = try resolveIosMirrorSwiftFile(arena, io, project_root);
    const sdk_swift_file = try resolveSdkSwiftApiFile(arena, io, project_root);
    const sdk_kotlin_file = try resolveSdkKotlinApiFile(arena, io, project_root);

    const zig_changed = try fs_util.writeFileIfChanged(arena, io, zig_file, zig_out);
    const zig_ffi_changed = try fs_util.writeFileIfChanged(arena, io, zig_ffi_root_file, zig_ffi_root_out);
    const zig_app_module_changed = try fs_util.writeFileIfChanged(arena, io, zig_app_module_file, zig_app_module_out);
    const swift_changed = try fs_util.writeFileIfChanged(arena, io, swift_file, swift_out);
    const kotlin_changed = try fs_util.writeFileIfChanged(arena, io, kotlin_file, kotlin_out);
    const android_jni_bridge_changed = try fs_util.writeFileIfChanged(arena, io, android_jni_bridge_file, android_jni_bridge_out);
    const android_jni_cmake_changed = try fs_util.writeFileIfChanged(arena, io, android_jni_cmake_file, android_jni_cmake_out);
    const ios_mirror_changed = if (ios_mirror_swift_file) |mirror_path|
        try fs_util.writeFileIfChanged(arena, io, mirror_path, swift_out)
    else
        false;
    const sdk_swift_changed = if (sdk_swift_file) |sdk_path|
        try fs_util.writeFileIfChanged(arena, io, sdk_path, swift_out)
    else
        false;
    const sdk_kotlin_changed = if (sdk_kotlin_file) |sdk_path|
        try fs_util.writeFileIfChanged(arena, io, sdk_path, kotlin_out)
    else
        false;
    const ios_host_patch_summary = ios_host_patch.ensureIosHostBuildPhase(arena, io, project_root) catch |err| blk: {
        try stderr.print("warning: failed to patch iOS host project for Wizig FFI build phase: {s}\n", .{@errorName(err)});
        break :blk ios_host_patch.PatchSummary{};
    };
    const android_project_root = try path_util.join(arena, project_root, "android");
    const android_host_patch_summary = if (fs_util.pathExists(io, android_project_root))
        android_gradle_migration.ensureBuildGradleKtsCompatibility(
            arena,
            io,
            android_project_root,
            "app",
        ) catch |err| blk: {
            try stderr.print("warning: failed to patch Android host Gradle for Wizig FFI build tasks: {s}\n", .{@errorName(err)});
            break :blk android_gradle_migration.MigrationSummary{};
        }
    else
        android_gradle_migration.MigrationSummary{};

    if (zig_changed or zig_ffi_changed or zig_app_module_changed or swift_changed or kotlin_changed or android_jni_bridge_changed or android_jni_cmake_changed or ios_mirror_changed or sdk_swift_changed or sdk_kotlin_changed) {
        try stdout.print("generated API bindings ({s})\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}", .{
            if (maybe_source) |source| if (source == .zig) "zig contract + discovery" else "json contract + discovery" else "auto-discovery",
            zig_file,
            zig_ffi_root_file,
            zig_app_module_file,
            swift_file,
            kotlin_file,
            android_jni_bridge_file,
            android_jni_cmake_file,
        });
        if (ios_mirror_swift_file) |mirror_path| {
            try stdout.print("\n- {s}", .{mirror_path});
        }
        if (sdk_swift_file) |sdk_path| {
            try stdout.print("\n- {s}", .{sdk_path});
        }
        if (sdk_kotlin_file) |sdk_path| {
            try stdout.print("\n- {s}", .{sdk_path});
        }
        try stdout.writeAll("\n");
    } else {
        try stdout.print("API bindings unchanged ({s})\n", .{
            if (maybe_source) |source| if (source == .zig) "zig contract + discovery" else "json contract + discovery" else "auto-discovery",
        });
    }
    if (ios_host_patch_summary.patched_projects > 0) {
        try stdout.print(
            "updated iOS host FFI build phase in {d}/{d} project(s)\n",
            .{ ios_host_patch_summary.patched_projects, ios_host_patch_summary.scanned_projects },
        );
    }
    if (android_host_patch_summary.patched) {
        try stdout.writeAll("updated Android host Gradle FFI task compatibility in app/build.gradle.kts\n");
    }
    try stdout.flush();
}

fn defaultApiSpecForProject(arena: std.mem.Allocator, project_root: []const u8) !ApiSpec {
    const tail = std.fs.path.basename(project_root);
    const candidate = if (tail.len > 0) tail else "app";
    const namespace = try std.fmt.allocPrint(arena, "dev.wizig.{s}", .{candidate});
    const empty_methods = try arena.alloc(ApiMethod, 0);
    const empty_events = try arena.alloc(ApiEvent, 0);
    return .{
        .namespace = namespace,
        .methods = empty_methods,
        .events = empty_events,
    };
}

fn resolveIosMirrorSwiftFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const ios_dir = try path_util.join(arena, project_root, "ios");
    if (!fs_util.pathExists(io, ios_dir)) return null;

    var ios = std.Io.Dir.cwd().openDir(io, ios_dir, .{ .iterate = true }) catch return null;
    defer ios.close(io);

    var walker = try ios.walk(arena);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.endsWith(u8, entry.path, ".xcodeproj")) continue;

        const project_name = std.fs.path.stem(entry.path);
        if (project_name.len == 0) continue;

        const host_dir = try path_util.join(arena, ios_dir, project_name);
        if (!fs_util.pathExists(io, host_dir)) continue;

        const generated_dir = try path_util.join(arena, host_dir, "Generated");
        try fs_util.ensureDir(io, generated_dir);
        const mirror_path = try path_util.join(arena, generated_dir, "WizigGeneratedApi.swift");
        return @as(?[]const u8, mirror_path);
    }

    return null;
}

fn resolveSdkSwiftApiFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const sdk_dir = try path_util.join(arena, project_root, ".wizig/sdk/ios/Sources/Wizig");
    if (!fs_util.pathExists(io, sdk_dir)) return null;
    const path = try path_util.join(arena, sdk_dir, "WizigGeneratedApi.swift");
    return @as(?[]const u8, path);
}

fn resolveSdkKotlinApiFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const sdk_dir = try path_util.join(arena, project_root, ".wizig/sdk/android/src/main/kotlin/dev/wizig");
    if (!fs_util.pathExists(io, sdk_dir)) return null;
    const path = try path_util.join(arena, sdk_dir, "WizigGeneratedApi.kt");
    return @as(?[]const u8, path);
}

const ApiType = enum {
    string,
    int,
    bool,
    void,
};

const ApiMethod = struct {
    name: []const u8,
    input: ApiType,
    output: ApiType,
};

const ApiEvent = struct {
    name: []const u8,
    payload: ApiType,
};

const ApiSpec = struct {
    namespace: []const u8,
    methods: []ApiMethod,
    events: []ApiEvent,
};

fn apiSourceFromPath(path: []const u8) !ApiContractSource {
    if (std.mem.endsWith(u8, path, ".zig")) return .zig;
    if (std.mem.endsWith(u8, path, ".json")) return .json;
    return error.InvalidContract;
}

fn parseApiSpecFromZig(arena: std.mem.Allocator, text: []const u8) !ApiSpec {
    var namespace: ?[]u8 = null;
    var methods = std.ArrayList(ApiMethod).empty;
    var events = std.ArrayList(ApiEvent).empty;

    errdefer {
        if (namespace) |value| arena.free(value);
        for (methods.items) |method| arena.free(method.name);
        methods.deinit(arena);
        for (events.items) |event| arena.free(event.name);
        events.deinit(arena);
    }

    const Section = enum { none, methods, events };
    var section: Section = .none;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "//")) continue;

        if (std.mem.startsWith(u8, line, "pub const namespace = ")) {
            const value = try extractQuotedField(arena, line, "pub const namespace = \"");
            if (namespace) |old| arena.free(old);
            namespace = value;
            continue;
        }

        if (std.mem.startsWith(u8, line, "pub const methods = .{")) {
            section = .methods;
            continue;
        }
        if (std.mem.startsWith(u8, line, "pub const events = .{")) {
            section = .events;
            continue;
        }
        if (std.mem.eql(u8, line, "};")) {
            section = .none;
            continue;
        }
        if (!std.mem.startsWith(u8, line, ".{")) continue;

        switch (section) {
            .methods => {
                const name = try extractQuotedField(arena, line, ".name = \"");
                const input = try parseTypeToken(try extractEnumToken(line, ".input = ."));
                const output = try parseTypeToken(try extractEnumToken(line, ".output = ."));
                try methods.append(arena, .{ .name = name, .input = input, .output = output });
            },
            .events => {
                const name = try extractQuotedField(arena, line, ".name = \"");
                const payload = try parseTypeToken(try extractEnumToken(line, ".payload = ."));
                try events.append(arena, .{ .name = name, .payload = payload });
            },
            .none => {},
        }
    }

    return .{
        .namespace = namespace orelse return error.InvalidContract,
        .methods = try methods.toOwnedSlice(arena),
        .events = try events.toOwnedSlice(arena),
    };
}

fn extractQuotedField(arena: std.mem.Allocator, line: []const u8, prefix: []const u8) ![]u8 {
    const start = std.mem.indexOf(u8, line, prefix) orelse return error.InvalidContract;
    const rest = line[start + prefix.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return error.InvalidContract;
    if (end == 0) return error.InvalidContract;
    return arena.dupe(u8, rest[0..end]);
}

fn extractEnumToken(line: []const u8, marker: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, line, marker) orelse return error.InvalidContract;
    const rest = line[start + marker.len ..];

    var end: usize = 0;
    while (end < rest.len) : (end += 1) {
        const ch = rest[end];
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_')) break;
    }
    if (end == 0) return error.InvalidContract;
    return rest[0..end];
}

fn parseTypeToken(token: []const u8) !ApiType {
    if (std.mem.eql(u8, token, "string")) return .string;
    if (std.mem.eql(u8, token, "int")) return .int;
    if (std.mem.eql(u8, token, "bool")) return .bool;
    if (std.mem.eql(u8, token, "void")) return .void;
    return error.InvalidContract;
}

fn parseApiSpecFromJson(arena: std.mem.Allocator, text: []const u8) !ApiSpec {
    const parsed = try std.json.parseFromSlice(std.json.Value, arena, text, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidContract;
    const root = parsed.value.object;

    const namespace = try dupRequiredString(arena, root, "namespace");
    errdefer arena.free(namespace);

    const methods_value = root.get("methods") orelse return error.InvalidContract;
    if (methods_value != .array) return error.InvalidContract;

    var methods = std.ArrayList(ApiMethod).empty;
    errdefer methods.deinit(arena);

    for (methods_value.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        const obj = item.object;

        const name = try dupRequiredString(arena, obj, "name");
        const input = try parseTypeField(obj, "input");
        const output = try parseTypeField(obj, "output");
        try methods.append(arena, .{ .name = name, .input = input, .output = output });
    }

    const events_value = root.get("events") orelse return error.InvalidContract;
    if (events_value != .array) return error.InvalidContract;

    var events = std.ArrayList(ApiEvent).empty;
    errdefer events.deinit(arena);

    for (events_value.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        const obj = item.object;

        const name = try dupRequiredString(arena, obj, "name");
        const payload = try parseTypeField(obj, "payload");
        try events.append(arena, .{ .name = name, .payload = payload });
    }

    return .{
        .namespace = namespace,
        .methods = try methods.toOwnedSlice(arena),
        .events = try events.toOwnedSlice(arena),
    };
}

fn dupRequiredString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    field: []const u8,
) ![]u8 {
    const value = object.get(field) orelse return error.InvalidContract;
    if (value != .string or value.string.len == 0) return error.InvalidContract;
    return allocator.dupe(u8, value.string);
}

fn parseTypeField(object: std.json.ObjectMap, field: []const u8) !ApiType {
    const value = object.get(field) orelse return error.InvalidContract;
    if (value != .string) return error.InvalidContract;
    return parseTypeToken(value.string);
}

fn mergeSpecWithDiscoveredMethods(
    arena: std.mem.Allocator,
    base_spec: ApiSpec,
    discovered: []const ApiMethod,
) !ApiSpec {
    var merged = std.ArrayList(ApiMethod).empty;
    errdefer merged.deinit(arena);

    for (base_spec.methods) |method| {
        try merged.append(arena, method);
    }
    for (discovered) |method| {
        var exists = false;
        for (merged.items) |existing| {
            if (!std.mem.eql(u8, existing.name, method.name)) continue;
            if (existing.input != method.input or existing.output != method.output) {
                return error.InvalidContract;
            }
            exists = true;
            break;
        }
        if (!exists) try merged.append(arena, method);
    }

    return .{
        .namespace = base_spec.namespace,
        .methods = try merged.toOwnedSlice(arena),
        .events = base_spec.events,
    };
}

fn discoverLibApiMethods(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const ApiMethod {
    const lib_dir = try path_util.join(arena, project_root, "lib");
    if (!fs_util.pathExists(io, lib_dir)) return &.{};

    var lib = std.Io.Dir.cwd().openDir(io, lib_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer lib.close(io);

    var walker = try lib.walk(arena);
    defer walker.deinit();

    var rel_paths = std.ArrayList([]const u8).empty;
    errdefer rel_paths.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        if (std.mem.eql(u8, entry.path, "WizigGeneratedAppModule.zig")) continue;

        const rel = try arena.dupe(u8, entry.path);
        for (rel) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        try rel_paths.append(arena, rel);
    }

    std.mem.sort([]const u8, rel_paths.items, {}, lessString);

    var discovered = std.ArrayList(ApiMethod).empty;
    errdefer discovered.deinit(arena);

    for (rel_paths.items) |rel_path| {
        const abs_path = try path_util.join(arena, lib_dir, rel_path);
        const source = std.Io.Dir.cwd().readFileAlloc(io, abs_path, arena, .limited(2 * 1024 * 1024)) catch continue;
        const methods = try parseApiMethodsFromLibSource(arena, source);
        for (methods) |method| {
            var exists = false;
            for (discovered.items) |existing| {
                if (std.mem.eql(u8, existing.name, method.name)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) try discovered.append(arena, method);
        }
    }

    return discovered.toOwnedSlice(arena);
}

fn parseApiMethodsFromLibSource(arena: std.mem.Allocator, source: []const u8) ![]const ApiMethod {
    var methods = std.ArrayList(ApiMethod).empty;
    errdefer methods.deinit(arena);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "pub fn ")) |start| {
        cursor = start + "pub fn ".len;
        while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}

        const name_start = cursor;
        if (name_start >= source.len or !isIdentStart(source[name_start])) continue;
        cursor += 1;
        while (cursor < source.len and isIdentContinue(source[cursor])) : (cursor += 1) {}
        const name = source[name_start..cursor];

        while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}
        if (cursor >= source.len or source[cursor] != '(') continue;

        const params_start = cursor + 1;
        cursor += 1;
        var depth: usize = 1;
        while (cursor < source.len and depth > 0) : (cursor += 1) {
            switch (source[cursor]) {
                '(' => depth += 1,
                ')' => depth -= 1,
                else => {},
            }
        }
        if (depth != 0 or cursor == 0) break;
        const params_end = cursor - 1;

        while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}
        const return_start = cursor;
        while (cursor < source.len and source[cursor] != '{' and source[cursor] != ';') : (cursor += 1) {}
        if (cursor <= return_start) continue;
        const return_raw = std.mem.trim(u8, source[return_start..cursor], " \t\r\n");

        if (try methodFromLibSignature(arena, name, source[params_start..params_end], return_raw)) |method| {
            try methods.append(arena, method);
        }
    }

    return methods.toOwnedSlice(arena);
}

fn methodFromLibSignature(
    arena: std.mem.Allocator,
    name: []const u8,
    params_raw: []const u8,
    return_raw: []const u8,
) !?ApiMethod {
    if (return_raw.len == 0) return null;

    var param_types = std.ArrayList([]const u8).empty;
    errdefer param_types.deinit(arena);

    var parts = std.mem.splitScalar(u8, params_raw, ',');
    while (parts.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t\r\n");
        if (part.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, part, ':') orelse return null;
        var ty = std.mem.trim(u8, part[colon + 1 ..], " \t\r\n");
        if (std.mem.indexOfScalar(u8, ty, '=')) |eq| {
            ty = std.mem.trim(u8, ty[0..eq], " \t\r\n");
        }
        try param_types.append(arena, try normalizeTypeToken(arena, ty));
    }

    var allocator_param = false;
    var input_type: ApiType = .void;
    switch (param_types.items.len) {
        0 => {},
        1 => {
            if (isAllocatorType(param_types.items[0])) {
                allocator_param = true;
            } else {
                input_type = parseLibParamType(param_types.items[0]) orelse return null;
            }
        },
        2 => {
            input_type = parseLibParamType(param_types.items[0]) orelse return null;
            if (!isAllocatorType(param_types.items[1])) return null;
            allocator_param = true;
        },
        else => return null,
    }

    var ret = std.mem.trim(u8, return_raw, " \t\r\n");
    if (ret.len == 0) return null;
    if (ret[0] == '!') ret = std.mem.trim(u8, ret[1..], " \t\r\n");
    const ret_norm = try normalizeTypeToken(arena, ret);
    const output_type = parseLibReturnType(ret_norm) orelse return null;

    if (output_type == .string and !allocator_param) return null;
    if (output_type != .string and allocator_param) return null;

    return .{
        .name = try arena.dupe(u8, name),
        .input = input_type,
        .output = output_type,
    };
}

fn normalizeTypeToken(arena: std.mem.Allocator, raw: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);
    for (raw) |ch| {
        if (std.ascii.isWhitespace(ch)) continue;
        try out.append(arena, ch);
    }
    return out.toOwnedSlice(arena);
}

fn isAllocatorType(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "std.mem.Allocator");
}

fn parseLibParamType(ty: []const u8) ?ApiType {
    if (std.mem.eql(u8, ty, "[]constu8") or std.mem.eql(u8, ty, "[]u8")) return .string;
    if (std.mem.eql(u8, ty, "i64")) return .int;
    if (std.mem.eql(u8, ty, "bool")) return .bool;
    return null;
}

fn parseLibReturnType(ty: []const u8) ?ApiType {
    if (std.mem.eql(u8, ty, "[]constu8") or std.mem.eql(u8, ty, "[]u8")) return .string;
    if (std.mem.eql(u8, ty, "i64")) return .int;
    if (std.mem.eql(u8, ty, "bool")) return .bool;
    if (std.mem.eql(u8, ty, "void")) return .void;
    return null;
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn isIdentContinue(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_';
}

fn renderZigApi(arena: std.mem.Allocator, spec: ApiSpec) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `wizig codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "const std = @import(\"std\");\n\n");

    try out.appendSlice(arena, "pub const WizigGeneratedApi = struct {\n");
    try out.appendSlice(arena, "    pub fn init() WizigGeneratedApi {\n");
    try out.appendSlice(arena, "        return .{};\n");
    try out.appendSlice(arena, "    }\n\n");

    for (spec.methods) |method| {
        const input_ty = zigType(method.input);
        const output_ty = zigType(method.output);
        if (method.output == .void) {
            try appendFmt(&out, arena, "    pub fn {s}(self: *const WizigGeneratedApi, input: {s}) void {{\n", .{ method.name, input_ty });
            try out.appendSlice(arena, "        _ = self;\n");
            try out.appendSlice(arena, "        _ = input;\n");
            try out.appendSlice(arena, "    }\n\n");
        } else {
            try appendFmt(&out, arena, "    pub fn {s}(self: *const WizigGeneratedApi, input: {s}, allocator: std.mem.Allocator) !{s} {{\n", .{ method.name, input_ty, output_ty });
            try out.appendSlice(arena, "        _ = self;\n");
            try out.appendSlice(arena, "        _ = allocator;\n");
            if (method.output == .string and method.input == .string) {
                try out.appendSlice(arena, "        return allocator.dupe(u8, input);\n");
            } else {
                try appendFmt(&out, arena, "        _ = input;\n        return {s};\n", .{zigDefaultValue(method.output)});
            }
            try out.appendSlice(arena, "    }\n\n");
        }
    }

    try out.appendSlice(arena, "};\n");
    return out.toOwnedSlice(arena);
}

fn renderZigFfiRoot(arena: std.mem.Allocator, spec: ApiSpec, compat: compatibility.Metadata) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `wizig codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "const std = @import(\"std\");\n");
    try out.appendSlice(arena, "const app = @import(\"wizig_app\");\n\n");

    try appendFmt(&out, arena, "const wizig_generated_abi_version: u32 = {d};\n", .{compat.abi_version});
    try appendFmt(&out, arena, "const wizig_generated_contract_hash: []const u8 = \"{s}\";\n\n", .{compat.contract_hash_hex});

    try out.appendSlice(arena, "pub const Status = enum(i32) {\n");
    try out.appendSlice(arena, "    ok = 0,\n");
    try out.appendSlice(arena, "    null_argument = 1,\n");
    try out.appendSlice(arena, "    out_of_memory = 2,\n");
    try out.appendSlice(arena, "    invalid_argument = 3,\n");
    try out.appendSlice(arena, "    internal_error = 255,\n");
    try out.appendSlice(arena, "};\n\n");

    try out.appendSlice(arena, "const ErrorDomain = enum(u32) {\n");
    try out.appendSlice(arena, "    none = 0,\n");
    try out.appendSlice(arena, "    argument = 1,\n");
    try out.appendSlice(arena, "    memory = 2,\n");
    try out.appendSlice(arena, "    runtime = 3,\n");
    try out.appendSlice(arena, "    compatibility = 4,\n");
    try out.appendSlice(arena, "};\n\n");

    try out.appendSlice(arena, "const LastError = struct {\n");
    try out.appendSlice(arena, "    domain: ErrorDomain = .none,\n");
    try out.appendSlice(arena, "    code: i32 = 0,\n");
    try out.appendSlice(arena, "    message: []const u8 = \"ok\",\n");
    try out.appendSlice(arena, "};\n\n");

    try out.appendSlice(arena, "threadlocal var last_error: LastError = .{};\n\n");

    try out.appendSlice(arena, "const allocator = std.heap.page_allocator;\n\n");
    try out.appendSlice(arena, "pub export fn getauxval(_: usize) usize {\n");
    try out.appendSlice(arena, "    return 0;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn statusCode(status: Status) i32 {\n");
    try out.appendSlice(arena, "    return @intFromEnum(status);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn domainLabel(domain: ErrorDomain) []const u8 {\n");
    try out.appendSlice(arena, "    return switch (domain) {\n");
    try out.appendSlice(arena, "        .none => \"wizig.ok\",\n");
    try out.appendSlice(arena, "        .argument => \"wizig.argument\",\n");
    try out.appendSlice(arena, "        .memory => \"wizig.memory\",\n");
    try out.appendSlice(arena, "        .runtime => \"wizig.runtime\",\n");
    try out.appendSlice(arena, "        .compatibility => \"wizig.compatibility\",\n");
    try out.appendSlice(arena, "    };\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn setLastError(domain: ErrorDomain, code: i32, message: []const u8) i32 {\n");
    try out.appendSlice(arena, "    last_error = .{ .domain = domain, .code = code, .message = message };\n");
    try out.appendSlice(arena, "    return code;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn clearLastError() void {\n");
    try out.appendSlice(arena, "    last_error = .{};\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_abi_version() u32 {\n");
    try out.appendSlice(arena, "    return wizig_generated_abi_version;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_contract_hash_ptr() [*]const u8 {\n");
    try out.appendSlice(arena, "    return wizig_generated_contract_hash.ptr;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_contract_hash_len() usize {\n");
    try out.appendSlice(arena, "    return wizig_generated_contract_hash.len;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_domain_ptr() [*]const u8 {\n");
    try out.appendSlice(arena, "    const label = domainLabel(last_error.domain);\n");
    try out.appendSlice(arena, "    return label.ptr;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_domain_len() usize {\n");
    try out.appendSlice(arena, "    return domainLabel(last_error.domain).len;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_code() i32 {\n");
    try out.appendSlice(arena, "    return last_error.code;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_message_ptr() [*]const u8 {\n");
    try out.appendSlice(arena, "    return last_error.message.ptr;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_message_len() usize {\n");
    try out.appendSlice(arena, "    return last_error.message.len;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_bytes_free(ptr: ?[*]u8, len: usize) void {\n");
    try out.appendSlice(arena, "    if (ptr == null) return;\n");
    try out.appendSlice(arena, "    allocator.free(ptr.?[0..len]);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn mapError(err: anyerror) i32 {\n");
    try out.appendSlice(arena, "    return switch (err) {\n");
    try out.appendSlice(arena, "        error.OutOfMemory => setLastError(.memory, statusCode(.out_of_memory), \"out of memory\"),\n");
    try out.appendSlice(arena, "        else => setLastError(.runtime, statusCode(.internal_error), @errorName(err)),\n");
    try out.appendSlice(arena, "    };\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn Unwrapped(comptime T: type) type {\n");
    try out.appendSlice(arena, "    return switch (@typeInfo(T)) {\n");
    try out.appendSlice(arena, "        .error_union => |info| info.payload,\n");
    try out.appendSlice(arena, "        else => T,\n");
    try out.appendSlice(arena, "    };\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn unwrapResult(value: anytype) !Unwrapped(@TypeOf(value)) {\n");
    try out.appendSlice(arena, "    return switch (@typeInfo(@TypeOf(value))) {\n");
    try out.appendSlice(arena, "        .error_union => value,\n");
    try out.appendSlice(arena, "        else => value,\n");
    try out.appendSlice(arena, "    };\n");
    try out.appendSlice(arena, "}\n\n");

    for (spec.methods) |method| {
        const export_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});

        if (method.output == .string) {
            switch (method.input) {
                .void => {
                    try appendFmt(
                        &out,
                        arena,
                        "pub export fn {s}(out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {{\n",
                        .{export_name},
                    );
                    try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
                    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
                    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
                    try out.appendSlice(arena, "    output_ptr.* = null;\n");
                    try out.appendSlice(arena, "    output_len.* = 0;\n");
                    try appendFmt(
                        &out,
                        arena,
                        "    const value = unwrapResult(app.{s}(allocator)) catch |err| return mapError(err);\n",
                        .{method.name},
                    );
                },
                .string => {
                    try appendFmt(
                        &out,
                        arena,
                        "pub export fn {s}(input_ptr: [*]const u8, input_len: usize, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {{\n",
                        .{export_name},
                    );
                    try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
                    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
                    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
                    try out.appendSlice(arena, "    output_ptr.* = null;\n");
                    try out.appendSlice(arena, "    output_len.* = 0;\n");
                    try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
                    try appendFmt(
                        &out,
                        arena,
                        "    const value = unwrapResult(app.{s}(input, allocator)) catch |err| return mapError(err);\n",
                        .{method.name},
                    );
                },
                .int => {
                    try appendFmt(
                        &out,
                        arena,
                        "pub export fn {s}(input: i64, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {{\n",
                        .{export_name},
                    );
                    try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
                    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
                    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
                    try out.appendSlice(arena, "    output_ptr.* = null;\n");
                    try out.appendSlice(arena, "    output_len.* = 0;\n");
                    try appendFmt(
                        &out,
                        arena,
                        "    const value = unwrapResult(app.{s}(input, allocator)) catch |err| return mapError(err);\n",
                        .{method.name},
                    );
                },
                .bool => {
                    try appendFmt(
                        &out,
                        arena,
                        "pub export fn {s}(input: u8, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {{\n",
                        .{export_name},
                    );
                    try out.appendSlice(arena, "    if (out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
                    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
                    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
                    try out.appendSlice(arena, "    output_ptr.* = null;\n");
                    try out.appendSlice(arena, "    output_len.* = 0;\n");
                    try out.appendSlice(arena, "    const input_bool = input != 0;\n");
                    try appendFmt(
                        &out,
                        arena,
                        "    const value = unwrapResult(app.{s}(input_bool, allocator)) catch |err| return mapError(err);\n",
                        .{method.name},
                    );
                },
            }

            try out.appendSlice(arena, "    const owned = allocator.dupe(u8, value) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
            try out.appendSlice(arena, "    output_ptr.* = owned.ptr;\n");
            try out.appendSlice(arena, "    output_len.* = owned.len;\n");
            try out.appendSlice(arena, "    clearLastError();\n");
            try out.appendSlice(arena, "    return statusCode(.ok);\n");
            try out.appendSlice(arena, "}\n\n");
            continue;
        }

        if (method.output == .int) {
            switch (method.input) {
                .void => try appendFmt(&out, arena, "pub export fn {s}(out_value: ?*i64) i32 {{\n", .{export_name}),
                .string => try appendFmt(&out, arena, "pub export fn {s}(input_ptr: [*]const u8, input_len: usize, out_value: ?*i64) i32 {{\n", .{export_name}),
                .int => try appendFmt(&out, arena, "pub export fn {s}(input: i64, out_value: ?*i64) i32 {{\n", .{export_name}),
                .bool => try appendFmt(&out, arena, "pub export fn {s}(input: u8, out_value: ?*i64) i32 {{\n", .{export_name}),
            }
            try out.appendSlice(arena, "    if (out_value == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
            if (method.input == .string) {
                try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
            } else if (method.input == .bool) {
                try out.appendSlice(arena, "    const input_bool = input != 0;\n");
            }
            switch (method.input) {
                .void => try appendFmt(&out, arena, "    const value = unwrapResult(app.{s}()) catch |err| return mapError(err);\n", .{method.name}),
                .string => try appendFmt(&out, arena, "    const value = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
                .int => try appendFmt(&out, arena, "    const value = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
                .bool => try appendFmt(&out, arena, "    const value = unwrapResult(app.{s}(input_bool)) catch |err| return mapError(err);\n", .{method.name}),
            }
            try out.appendSlice(arena, "    out_value.?.* = value;\n");
            try out.appendSlice(arena, "    clearLastError();\n");
            try out.appendSlice(arena, "    return statusCode(.ok);\n");
            try out.appendSlice(arena, "}\n\n");
            continue;
        }

        if (method.output == .bool) {
            switch (method.input) {
                .void => try appendFmt(&out, arena, "pub export fn {s}(out_value: ?*u8) i32 {{\n", .{export_name}),
                .string => try appendFmt(&out, arena, "pub export fn {s}(input_ptr: [*]const u8, input_len: usize, out_value: ?*u8) i32 {{\n", .{export_name}),
                .int => try appendFmt(&out, arena, "pub export fn {s}(input: i64, out_value: ?*u8) i32 {{\n", .{export_name}),
                .bool => try appendFmt(&out, arena, "pub export fn {s}(input: u8, out_value: ?*u8) i32 {{\n", .{export_name}),
            }
            try out.appendSlice(arena, "    if (out_value == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
            if (method.input == .string) {
                try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
            } else if (method.input == .bool) {
                try out.appendSlice(arena, "    const input_bool = input != 0;\n");
            }
            switch (method.input) {
                .void => try appendFmt(&out, arena, "    const value = unwrapResult(app.{s}()) catch |err| return mapError(err);\n", .{method.name}),
                .string => try appendFmt(&out, arena, "    const value = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
                .int => try appendFmt(&out, arena, "    const value = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
                .bool => try appendFmt(&out, arena, "    const value = unwrapResult(app.{s}(input_bool)) catch |err| return mapError(err);\n", .{method.name}),
            }
            try out.appendSlice(arena, "    out_value.?.* = if (value) 1 else 0;\n");
            try out.appendSlice(arena, "    clearLastError();\n");
            try out.appendSlice(arena, "    return statusCode(.ok);\n");
            try out.appendSlice(arena, "}\n\n");
            continue;
        }

        // void output
        switch (method.input) {
            .void => try appendFmt(&out, arena, "pub export fn {s}() i32 {{\n", .{export_name}),
            .string => try appendFmt(&out, arena, "pub export fn {s}(input_ptr: [*]const u8, input_len: usize) i32 {{\n", .{export_name}),
            .int => try appendFmt(&out, arena, "pub export fn {s}(input: i64) i32 {{\n", .{export_name}),
            .bool => try appendFmt(&out, arena, "pub export fn {s}(input: u8) i32 {{\n", .{export_name}),
        }
        if (method.input == .string) {
            try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
        } else if (method.input == .bool) {
            try out.appendSlice(arena, "    const input_bool = input != 0;\n");
        }
        switch (method.input) {
            .void => try appendFmt(&out, arena, "    _ = unwrapResult(app.{s}()) catch |err| return mapError(err);\n", .{method.name}),
            .string => try appendFmt(&out, arena, "    _ = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
            .int => try appendFmt(&out, arena, "    _ = unwrapResult(app.{s}(input)) catch |err| return mapError(err);\n", .{method.name}),
            .bool => try appendFmt(&out, arena, "    _ = unwrapResult(app.{s}(input_bool)) catch |err| return mapError(err);\n", .{method.name}),
        }
        try out.appendSlice(arena, "    clearLastError();\n");
        try out.appendSlice(arena, "    return statusCode(.ok);\n");
        try out.appendSlice(arena, "}\n\n");
    }

    return out.toOwnedSlice(arena);
}

fn collectLibModuleImports(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
    const lib_dir = try path_util.join(arena, project_root, "lib");
    if (!fs_util.pathExists(io, lib_dir)) return &.{};

    var lib = std.Io.Dir.cwd().openDir(io, lib_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer lib.close(io);

    var walker = try lib.walk(arena);
    defer walker.deinit();

    var imports = std.ArrayList([]const u8).empty;
    errdefer imports.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;

        const rel = try arena.dupe(u8, entry.path);
        for (rel) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        if (std.mem.eql(u8, rel, "WizigGeneratedAppModule.zig")) continue;
        const import_path = try arena.dupe(u8, rel);
        try imports.append(arena, import_path);
    }

    std.mem.sort([]const u8, imports.items, {}, lessString);
    return imports.toOwnedSlice(arena);
}

const ZigWrapperShape = struct {
    args: []const u8,
    call_args: []const u8,
    return_ty: []const u8,
};

fn zigWrapperShape(method: ApiMethod) ZigWrapperShape {
    const return_ty = switch (method.output) {
        .string => "![]const u8",
        .int => "!i64",
        .bool => "!bool",
        .void => "!void",
    };

    return switch (method.input) {
        .void => if (method.output == .string)
            .{
                .args = "allocator: std.mem.Allocator",
                .call_args = "allocator",
                .return_ty = return_ty,
            }
        else
            .{
                .args = "",
                .call_args = "",
                .return_ty = return_ty,
            },
        .string => if (method.output == .string)
            .{
                .args = "input: []const u8, allocator: std.mem.Allocator",
                .call_args = "input, allocator",
                .return_ty = return_ty,
            }
        else
            .{
                .args = "input: []const u8",
                .call_args = "input",
                .return_ty = return_ty,
            },
        .int => if (method.output == .string)
            .{
                .args = "input: i64, allocator: std.mem.Allocator",
                .call_args = "input, allocator",
                .return_ty = return_ty,
            }
        else
            .{
                .args = "input: i64",
                .call_args = "input",
                .return_ty = return_ty,
            },
        .bool => if (method.output == .string)
            .{
                .args = "input: bool, allocator: std.mem.Allocator",
                .call_args = "input, allocator",
                .return_ty = return_ty,
            }
        else
            .{
                .args = "input: bool",
                .call_args = "input",
                .return_ty = return_ty,
            },
    };
}

fn renderZigAppModule(
    arena: std.mem.Allocator,
    spec: ApiSpec,
    module_imports: []const []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `wizig codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "const std = @import(\"std\");\n\n");

    for (module_imports, 0..) |import_path, idx| {
        try appendFmt(&out, arena, "const module_{d} = @import(\"{s}\");\n", .{ idx, import_path });
    }
    if (module_imports.len > 0) {
        try out.appendSlice(arena, "\n");
    }

    const main_module_path = "main.zig";
    const main_module_index = blk: {
        for (module_imports, 0..) |import_path, idx| {
            if (std.mem.eql(u8, import_path, main_module_path)) break :blk idx;
        }
        break :blk @as(?usize, null);
    };

    for (spec.methods) |method| {
        const shape = zigWrapperShape(method);
        if (shape.args.len == 0) {
            try appendFmt(&out, arena, "pub fn {s}() {s} {{\n", .{ method.name, shape.return_ty });
        } else {
            try appendFmt(&out, arena, "pub fn {s}({s}) {s} {{\n", .{ method.name, shape.args, shape.return_ty });
        }

        const indent = if (main_module_index != null) "        " else "    ";
        if (main_module_index) |idx| {
            if (shape.call_args.len == 0) {
                try appendFmt(
                    &out,
                    arena,
                    "    if (@hasDecl(module_{d}, \"{s}\")) return module_{d}.{s}();\n",
                    .{ idx, method.name, idx, method.name },
                );
            } else {
                try appendFmt(
                    &out,
                    arena,
                    "    if (@hasDecl(module_{d}, \"{s}\")) return module_{d}.{s}({s});\n",
                    .{ idx, method.name, idx, method.name, shape.call_args },
                );
            }
            try appendFmt(&out, arena, "    if (!@hasDecl(module_{d}, \"{s}\")) {{\n", .{ idx, method.name });
        }

        try appendFmt(&out, arena, "{s}const candidate_count: comptime_int = 0", .{indent});
        for (module_imports, 0..) |_, idx| {
            if (main_module_index != null and idx == main_module_index.?) continue;
            try appendFmt(
                &out,
                arena,
                " + @as(comptime_int, if (@hasDecl(module_{d}, \"{s}\")) 1 else 0)",
                .{ idx, method.name },
            );
        }
        try out.appendSlice(arena, ";\n");
        try appendFmt(
            &out,
            arena,
            "{s}if (candidate_count == 0) @compileError(\"wizig codegen: no implementation found for API method '{s}' across lib/**/*.zig\");\n",
            .{ indent, method.name },
        );
        try appendFmt(
            &out,
            arena,
            "{s}if (candidate_count > 1) @compileError(\"wizig codegen: multiple implementations found for API method '{s}' across lib/**/*.zig (define once, or keep only lib/main.zig)\");\n",
            .{ indent, method.name },
        );

        for (module_imports, 0..) |_, idx| {
            if (main_module_index != null and idx == main_module_index.?) continue;
            if (shape.call_args.len == 0) {
                try appendFmt(
                    &out,
                    arena,
                    "{s}if (@hasDecl(module_{d}, \"{s}\")) return module_{d}.{s}();\n",
                    .{ indent, idx, method.name, idx, method.name },
                );
            } else {
                try appendFmt(
                    &out,
                    arena,
                    "{s}if (@hasDecl(module_{d}, \"{s}\")) return module_{d}.{s}({s});\n",
                    .{ indent, idx, method.name, idx, method.name, shape.call_args },
                );
            }
        }

        try appendFmt(&out, arena, "{s}unreachable;\n", .{indent});
        if (main_module_index != null) {
            try out.appendSlice(arena, "    }\n");
        }
        try out.appendSlice(arena, "}\n\n");
    }

    return out.toOwnedSlice(arena);
}

fn renderSwiftApi(arena: std.mem.Allocator, spec: ApiSpec, compat: compatibility.Metadata) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `wizig codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "import Darwin\n");
    try out.appendSlice(arena, "import Foundation\n\n");

    try appendFmt(&out, arena, "private let wizigExpectedAbiVersion: UInt32 = {d}\n", .{compat.abi_version});
    try appendFmt(&out, arena, "private let wizigExpectedContractHash = \"{s}\"\n\n", .{compat.contract_hash_hex});

    try out.appendSlice(arena, "public protocol WizigGeneratedEventSink: AnyObject {\n");
    for (spec.events) |event| {
        const event_name = try upperCamel(arena, event.name);
        try appendFmt(&out, arena, "    func on{s}(payload: {s})\n", .{ event_name, swiftType(event.payload) });
    }
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "public enum WizigGeneratedApiError: Error, CustomStringConvertible {\n");
    try out.appendSlice(arena, "    case ffiLibraryLoadFailed(String)\n");
    try out.appendSlice(arena, "    case ffiSymbolMissing(String)\n");
    try out.appendSlice(arena, "    case ffiCallFailed(function: String, domain: String, code: Int32, message: String)\n");
    try out.appendSlice(arena, "    case compatibilityMismatch(expectedAbi: UInt32, actualAbi: UInt32, expectedContractHash: String, actualContractHash: String)\n");
    try out.appendSlice(arena, "    case bindingValidationFailed(String)\n");
    try out.appendSlice(arena, "    case invalidUtf8(function: String)\n");
    try out.appendSlice(arena, "    case unexpectedNullOutput(function: String)\n\n");
    try out.appendSlice(arena, "    public var description: String {\n");
    try out.appendSlice(arena, "        switch self {\n");
    try out.appendSlice(arena, "        case let .ffiLibraryLoadFailed(reason):\n");
    try out.appendSlice(arena, "            return \"failed to load Wizig FFI library: \\(reason)\"\n");
    try out.appendSlice(arena, "        case let .ffiSymbolMissing(name):\n");
    try out.appendSlice(arena, "            return \"missing Wizig FFI symbol: \\(name)\"\n");
    try out.appendSlice(arena, "        case let .ffiCallFailed(function, domain, code, message):\n");
    try out.appendSlice(arena, "            return \"FFI call failed: \\(function) domain=\\(domain) code=\\(code) message=\\(message)\"\n");
    try out.appendSlice(arena, "        case let .compatibilityMismatch(expectedAbi, actualAbi, expectedContractHash, actualContractHash):\n");
    try out.appendSlice(arena, "            return \"FFI compatibility mismatch: abi expected \\(expectedAbi), got \\(actualAbi); contract expected \\(expectedContractHash), got \\(actualContractHash)\"\n");
    try out.appendSlice(arena, "        case let .bindingValidationFailed(reason):\n");
    try out.appendSlice(arena, "            return \"Wizig generated API binding validation failed: \\(reason)\"\n");
    try out.appendSlice(arena, "        case let .invalidUtf8(function):\n");
    try out.appendSlice(arena, "            return \"\\(function) returned non-UTF-8 output\"\n");
    try out.appendSlice(arena, "        case let .unexpectedNullOutput(function):\n");
    try out.appendSlice(arena, "            return \"\\(function) returned null output\"\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "private enum WizigGeneratedStatus: Int32 {\n");
    try out.appendSlice(arena, "    case ok = 0\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "private final class WizigGeneratedFFI {\n");
    try out.appendSlice(arena, "    typealias BytesFreeFn = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void\n\n");
    try out.appendSlice(arena, "    typealias AbiVersionFn = @convention(c) () -> UInt32\n");
    try out.appendSlice(arena, "    typealias ContractHashPtrFn = @convention(c) () -> UnsafePointer<UInt8>\n");
    try out.appendSlice(arena, "    typealias ContractHashLenFn = @convention(c) () -> Int\n");
    try out.appendSlice(arena, "    typealias LastErrorDomainPtrFn = @convention(c) () -> UnsafePointer<UInt8>\n");
    try out.appendSlice(arena, "    typealias LastErrorDomainLenFn = @convention(c) () -> Int\n");
    try out.appendSlice(arena, "    typealias LastErrorCodeFn = @convention(c) () -> Int32\n");
    try out.appendSlice(arena, "    typealias LastErrorMessagePtrFn = @convention(c) () -> UnsafePointer<UInt8>\n");
    try out.appendSlice(arena, "    typealias LastErrorMessageLenFn = @convention(c) () -> Int\n\n");
    try out.appendSlice(arena, "    let bytesFree: BytesFreeFn\n");
    try out.appendSlice(arena, "    let abiVersion: AbiVersionFn\n");
    try out.appendSlice(arena, "    let contractHashPtr: ContractHashPtrFn\n");
    try out.appendSlice(arena, "    let contractHashLen: ContractHashLenFn\n");
    try out.appendSlice(arena, "    let lastErrorDomainPtr: LastErrorDomainPtrFn\n");
    try out.appendSlice(arena, "    let lastErrorDomainLen: LastErrorDomainLenFn\n");
    try out.appendSlice(arena, "    let lastErrorCode: LastErrorCodeFn\n");
    try out.appendSlice(arena, "    let lastErrorMessagePtr: LastErrorMessagePtrFn\n");
    try out.appendSlice(arena, "    let lastErrorMessageLen: LastErrorMessageLenFn\n");
    try out.appendSlice(arena, "    private let libraryHandle: UnsafeMutableRawPointer\n\n");
    try out.appendSlice(arena, "    init(libraryPath: String?) throws {\n");
    try out.appendSlice(arena, "        let candidates: [String] = {\n");
    try out.appendSlice(arena, "            if let libraryPath, !libraryPath.isEmpty {\n");
    try out.appendSlice(arena, "                return [libraryPath]\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "            var values = [String]()\n");
    try out.appendSlice(arena, "            if let fromEnv = ProcessInfo.processInfo.environment[\"WIZIG_FFI_LIB\"], !fromEnv.isEmpty {\n");
    try out.appendSlice(arena, "                values.append(fromEnv)\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "            values.append(contentsOf: [\"libwizigffi.dylib\", \"wizigffi\"])\n");
    try out.appendSlice(arena, "            return values\n");
    try out.appendSlice(arena, "        }()\n\n");
    try out.appendSlice(arena, "        var lastError = \"no candidate library path\"\n");
    try out.appendSlice(arena, "        var handle: UnsafeMutableRawPointer?\n");
    try out.appendSlice(arena, "        for candidate in candidates {\n");
    try out.appendSlice(arena, "            _ = dlerror()\n");
    try out.appendSlice(arena, "            if let loaded = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) {\n");
    try out.appendSlice(arena, "                handle = loaded\n");
    try out.appendSlice(arena, "                break\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "            if let err = dlerror() {\n");
    try out.appendSlice(arena, "                lastError = String(cString: err)\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n\n");
    try out.appendSlice(arena, "        guard let handle else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.ffiLibraryLoadFailed(lastError)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        self.libraryHandle = handle\n");
    try out.appendSlice(arena, "        self.bytesFree = try Self.loadSymbol(handle, name: \"wizig_bytes_free\")\n");
    try out.appendSlice(arena, "        self.abiVersion = try Self.loadSymbol(handle, name: \"wizig_ffi_abi_version\")\n");
    try out.appendSlice(arena, "        self.contractHashPtr = try Self.loadSymbol(handle, name: \"wizig_ffi_contract_hash_ptr\")\n");
    try out.appendSlice(arena, "        self.contractHashLen = try Self.loadSymbol(handle, name: \"wizig_ffi_contract_hash_len\")\n");
    try out.appendSlice(arena, "        self.lastErrorDomainPtr = try Self.loadSymbol(handle, name: \"wizig_ffi_last_error_domain_ptr\")\n");
    try out.appendSlice(arena, "        self.lastErrorDomainLen = try Self.loadSymbol(handle, name: \"wizig_ffi_last_error_domain_len\")\n");
    try out.appendSlice(arena, "        self.lastErrorCode = try Self.loadSymbol(handle, name: \"wizig_ffi_last_error_code\")\n");
    try out.appendSlice(arena, "        self.lastErrorMessagePtr = try Self.loadSymbol(handle, name: \"wizig_ffi_last_error_message_ptr\")\n");
    try out.appendSlice(arena, "        self.lastErrorMessageLen = try Self.loadSymbol(handle, name: \"wizig_ffi_last_error_message_len\")\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    deinit {\n");
    try out.appendSlice(arena, "        _ = dlclose(libraryHandle)\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    func loadSymbol<T>(_ name: String, as: T.Type = T.self) throws -> T {\n");
    try out.appendSlice(arena, "        try Self.loadSymbol(libraryHandle, name: name)\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private static func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, name: String) throws -> T {\n");
    try out.appendSlice(arena, "        _ = dlerror()\n");
    try out.appendSlice(arena, "        guard let symbol = dlsym(handle, name) else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.ffiSymbolMissing(name)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return unsafeBitCast(symbol, to: T.self)\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "\n");
    try out.appendSlice(arena, "    private func decodeUtf8(ptr: UnsafePointer<UInt8>, len: Int) -> String {\n");
    try out.appendSlice(arena, "        guard len > 0 else { return \"\" }\n");
    try out.appendSlice(arena, "        let data = Data(bytes: ptr, count: len)\n");
    try out.appendSlice(arena, "        return String(data: data, encoding: .utf8) ?? \"\"\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "\n");
    try out.appendSlice(arena, "    func readContractHash() -> String {\n");
    try out.appendSlice(arena, "        decodeUtf8(ptr: contractHashPtr(), len: contractHashLen())\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "\n");
    try out.appendSlice(arena, "    func readLastError() -> (domain: String, code: Int32, message: String) {\n");
    try out.appendSlice(arena, "        let domain = decodeUtf8(ptr: lastErrorDomainPtr(), len: lastErrorDomainLen())\n");
    try out.appendSlice(arena, "        let code = lastErrorCode()\n");
    try out.appendSlice(arena, "        let message = decodeUtf8(ptr: lastErrorMessagePtr(), len: lastErrorMessageLen())\n");
    try out.appendSlice(arena, "        return (domain, code, message)\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "public final class WizigGeneratedApi {\n");
    try out.appendSlice(arena, "    public weak var sink: WizigGeneratedEventSink?\n");
    try out.appendSlice(arena, "    private let ffi: WizigGeneratedFFI\n\n");
    try out.appendSlice(arena, "    public init(libraryPath: String? = nil, sink: WizigGeneratedEventSink? = nil) throws {\n");
    try out.appendSlice(arena, "        self.ffi = try WizigGeneratedFFI(libraryPath: libraryPath)\n");
    try out.appendSlice(arena, "        self.sink = sink\n");
    try out.appendSlice(arena, "        try validateBindings()\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private func validateBindings() throws {\n");
    try out.appendSlice(arena, "        let requiredSymbols = [\n");
    try out.appendSlice(arena, "            \"wizig_ffi_abi_version\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_contract_hash_ptr\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_contract_hash_len\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_domain_ptr\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_domain_len\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_code\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_message_ptr\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_message_len\",\n");
    for (spec.methods) |method| {
        try appendFmt(&out, arena, "            \"wizig_api_{s}\",\n", .{method.name});
    }
    try out.appendSlice(arena, "        ]\n");
    try out.appendSlice(arena, "        for symbol in requiredSymbols {\n");
    try out.appendSlice(arena, "            do {\n");
    try out.appendSlice(arena, "                _ = try ffi.loadSymbol(symbol, as: UnsafeMutableRawPointer.self)\n");
    try out.appendSlice(arena, "            } catch {\n");
    try out.appendSlice(arena, "                throw WizigGeneratedApiError.bindingValidationFailed(\"\\(symbol): \\(error)\")\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        let actualAbi = ffi.abiVersion()\n");
    try out.appendSlice(arena, "        let actualContractHash = ffi.readContractHash()\n");
    try out.appendSlice(arena, "        guard actualAbi == wizigExpectedAbiVersion, actualContractHash == wizigExpectedContractHash else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.compatibilityMismatch(\n");
    try out.appendSlice(arena, "                expectedAbi: wizigExpectedAbiVersion,\n");
    try out.appendSlice(arena, "                actualAbi: actualAbi,\n");
    try out.appendSlice(arena, "                expectedContractHash: wizigExpectedContractHash,\n");
    try out.appendSlice(arena, "                actualContractHash: actualContractHash\n");
    try out.appendSlice(arena, "            )\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private func ensureStatus(_ status: Int32, function: String) throws {\n");
    try out.appendSlice(arena, "        guard status == WizigGeneratedStatus.ok.rawValue else {\n");
    try out.appendSlice(arena, "            let detail = ffi.readLastError()\n");
    try out.appendSlice(arena, "            let resolvedCode = detail.code == 0 ? status : detail.code\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.ffiCallFailed(function: function, domain: detail.domain, code: resolvedCode, message: detail.message)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private func withUTF8Pointer<T>(_ value: String, _ body: (UnsafePointer<UInt8>, Int) throws -> T) throws -> T {\n");
    try out.appendSlice(arena, "        let bytes = Array(value.utf8)\n");
    try out.appendSlice(arena, "        if bytes.isEmpty {\n");
    try out.appendSlice(arena, "            var placeholder: UInt8 = 0\n");
    try out.appendSlice(arena, "            return try withUnsafePointer(to: &placeholder) { ptr in\n");
    try out.appendSlice(arena, "                try body(ptr, 0)\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return try bytes.withUnsafeBufferPointer { buffer in\n");
    try out.appendSlice(arena, "            try body(buffer.baseAddress!, buffer.count)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private func callStringOutput(function: String, _ invoke: (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, UnsafeMutablePointer<Int>) -> Int32) throws -> String {\n");
    try out.appendSlice(arena, "        var outPtr: UnsafeMutablePointer<UInt8>?\n");
    try out.appendSlice(arena, "        var outLen = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&outPtr, &outLen), function: function)\n");
    try out.appendSlice(arena, "        guard let outPtr else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.unexpectedNullOutput(function: function)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        defer {\n");
    try out.appendSlice(arena, "            ffi.bytesFree(outPtr, outLen)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        let data = Data(bytes: outPtr, count: outLen)\n");
    try out.appendSlice(arena, "        guard let value = String(data: data, encoding: .utf8) else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.invalidUtf8(function: function)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return value\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private func callIntOutput(function: String, _ invoke: (UnsafeMutablePointer<Int64>) -> Int32) throws -> Int64 {\n");
    try out.appendSlice(arena, "        var out: Int64 = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&out), function: function)\n");
    try out.appendSlice(arena, "        return out\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private func callBoolOutput(function: String, _ invoke: (UnsafeMutablePointer<UInt8>) -> Int32) throws -> Bool {\n");
    try out.appendSlice(arena, "        var out: UInt8 = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&out), function: function)\n");
    try out.appendSlice(arena, "        return out != 0\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private func callVoidOutput(function: String, _ invoke: () -> Int32) throws {\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(), function: function)\n");
    try out.appendSlice(arena, "    }\n\n");

    for (spec.methods) |method| {
        const symbol_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});
        const params = if (method.input == .void)
            "()"
        else
            try std.fmt.allocPrint(arena, "(_ input: {s})", .{swiftType(method.input)});

        if (method.output == .void) {
            try appendFmt(&out, arena, "    public func {s}{s} throws {{\n", .{ method.name, params });
        } else {
            try appendFmt(&out, arena, "    public func {s}{s} throws -> {s} {{\n", .{ method.name, params, swiftType(method.output) });
        }

        if (method.output == .string) {
            switch (method.input) {
                .void => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try appendFmt(&out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(outPtr, outLen)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .string => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
                    try appendFmt(&out, arena, "            try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{symbol_name});
                    try out.appendSlice(arena, "                fn(inputPtr, inputLen, outPtr, outLen)\n");
                    try out.appendSlice(arena, "            }\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .int => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (Int64, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try appendFmt(&out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(input, outPtr, outLen)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .bool => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UInt8, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
                    try appendFmt(&out, arena, "        return try callStringOutput(function: \"{s}\") {{ outPtr, outLen in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(inputFlag, outPtr, outLen)\n");
                    try out.appendSlice(arena, "        }\n");
                },
            }
        } else if (method.output == .int) {
            switch (method.input) {
                .void => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafeMutablePointer<Int64>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try appendFmt(&out, arena, "        return try callIntOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .string => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Int64>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
                    try appendFmt(&out, arena, "            try callIntOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "                fn(inputPtr, inputLen, outValue)\n");
                    try out.appendSlice(arena, "            }\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .int => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (Int64, UnsafeMutablePointer<Int64>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try appendFmt(&out, arena, "        return try callIntOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(input, outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .bool => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UInt8, UnsafeMutablePointer<Int64>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
                    try appendFmt(&out, arena, "        return try callIntOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(inputFlag, outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
            }
        } else if (method.output == .bool) {
            switch (method.input) {
                .void => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try appendFmt(&out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .string => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UInt8>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        return try withUTF8Pointer(input) { inputPtr, inputLen in\n");
                    try appendFmt(&out, arena, "            try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "                fn(inputPtr, inputLen, outValue)\n");
                    try out.appendSlice(arena, "            }\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .int => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (Int64, UnsafeMutablePointer<UInt8>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try appendFmt(&out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(input, outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .bool => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UInt8, UnsafeMutablePointer<UInt8>?) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
                    try appendFmt(&out, arena, "        return try callBoolOutput(function: \"{s}\") {{ outValue in\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(inputFlag, outValue)\n");
                    try out.appendSlice(arena, "        }\n");
                },
            }
        } else {
            switch (method.input) {
                .void => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) () -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try appendFmt(&out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn()\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .string => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UnsafePointer<UInt8>, Int) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        try withUTF8Pointer(input) { inputPtr, inputLen in\n");
                    try appendFmt(&out, arena, "            try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                    try out.appendSlice(arena, "                fn(inputPtr, inputLen)\n");
                    try out.appendSlice(arena, "            }\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .int => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (Int64) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try appendFmt(&out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(input)\n");
                    try out.appendSlice(arena, "        }\n");
                },
                .bool => {
                    try out.appendSlice(arena, "        typealias Fn = @convention(c) (UInt8) -> Int32\n");
                    try appendFmt(&out, arena, "        let fn: Fn = try ffi.loadSymbol(\"{s}\")\n", .{symbol_name});
                    try out.appendSlice(arena, "        let inputFlag: UInt8 = input ? 1 : 0\n");
                    try appendFmt(&out, arena, "        try callVoidOutput(function: \"{s}\") {{\n", .{symbol_name});
                    try out.appendSlice(arena, "            fn(inputFlag)\n");
                    try out.appendSlice(arena, "        }\n");
                },
            }
        }
        try out.appendSlice(arena, "    }\n\n");
    }

    for (spec.events) |event| {
        const event_name = try upperCamel(arena, event.name);
        try appendFmt(&out, arena, "    public func emit{s}(payload: {s}) {{\n", .{ event_name, swiftType(event.payload) });
        try appendFmt(&out, arena, "        sink?.on{s}(payload: payload)\n", .{event_name});
        try out.appendSlice(arena, "    }\n\n");
    }

    try out.appendSlice(arena, "}\n");
    return out.toOwnedSlice(arena);
}

fn renderKotlinApi(arena: std.mem.Allocator, spec: ApiSpec, compat: compatibility.Metadata) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `wizig codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "package dev.wizig\n\n");

    try appendFmt(&out, arena, "private const val WIZIG_EXPECTED_ABI_VERSION: Int = {d}\n", .{compat.abi_version});
    try appendFmt(&out, arena, "private const val WIZIG_EXPECTED_CONTRACT_HASH: String = \"{s}\"\n\n", .{compat.contract_hash_hex});

    try out.appendSlice(arena, "interface WizigGeneratedEventSink {\n");
    for (spec.events) |event| {
        try appendFmt(&out, arena, "    fun on{s}(payload: {s})\n", .{ try upperCamel(arena, event.name), kotlinType(event.payload) });
    }
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "class WizigGeneratedFfiException(\n");
    try out.appendSlice(arena, "    val domain: String,\n");
    try out.appendSlice(arena, "    val code: Int,\n");
    try out.appendSlice(arena, "    val detail: String,\n");
    try out.appendSlice(arena, ") : RuntimeException(\"$domain[$code]: $detail\")\n\n");

    try out.appendSlice(arena, "private object WizigGeneratedNativeBridge {\n");
    try out.appendSlice(arena, "    init {\n");
    try out.appendSlice(arena, "        System.loadLibrary(\"wizigffi\")\n");
    try out.appendSlice(arena, "        System.loadLibrary(\"wizigjni\")\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    @JvmStatic external fun wizig_validate_bindings()\n");
    for (spec.methods) |method| {
        const ffi_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});
        if (method.input == .void) {
            try appendFmt(&out, arena, "    @JvmStatic external fun {s}(): {s}\n", .{ ffi_name, kotlinType(method.output) });
        } else {
            try appendFmt(
                &out,
                arena,
                "    @JvmStatic external fun {s}(input: {s}): {s}\n",
                .{ ffi_name, kotlinType(method.input), kotlinType(method.output) },
            );
        }
    }
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "class WizigGeneratedApi(\n");
    try out.appendSlice(arena, "    private var sink: WizigGeneratedEventSink? = null,\n");
    try out.appendSlice(arena, ") {\n");
    try out.appendSlice(arena, "    init {\n");
    try out.appendSlice(arena, "        WizigGeneratedNativeBridge\n");
    try out.appendSlice(arena, "        WizigGeneratedNativeBridge.wizig_validate_bindings()\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    fun setEventSink(next: WizigGeneratedEventSink?) {\n");
    try out.appendSlice(arena, "        sink = next\n");
    try out.appendSlice(arena, "    }\n\n");

    for (spec.methods) |method| {
        const ffi_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});
        if (method.input == .void) {
            if (method.output == .void) {
                try appendFmt(&out, arena, "    fun {s}() {{\n", .{method.name});
                try appendFmt(&out, arena, "        WizigGeneratedNativeBridge.{s}()\n", .{ffi_name});
            } else {
                try appendFmt(&out, arena, "    fun {s}(): {s} {{\n", .{ method.name, kotlinType(method.output) });
                try appendFmt(&out, arena, "        return WizigGeneratedNativeBridge.{s}()\n", .{ffi_name});
            }
        } else {
            if (method.output == .void) {
                try appendFmt(&out, arena, "    fun {s}(input: {s}) {{\n", .{ method.name, kotlinType(method.input) });
                try appendFmt(&out, arena, "        WizigGeneratedNativeBridge.{s}(input)\n", .{ffi_name});
            } else {
                try appendFmt(&out, arena, "    fun {s}(input: {s}): {s} {{\n", .{ method.name, kotlinType(method.input), kotlinType(method.output) });
                try appendFmt(&out, arena, "        return WizigGeneratedNativeBridge.{s}(input)\n", .{ffi_name});
            }
        }
        try out.appendSlice(arena, "    }\n\n");
    }

    for (spec.events) |event| {
        const event_name = try upperCamel(arena, event.name);
        try appendFmt(&out, arena, "    fun emit{s}(payload: {s}) {{\n", .{ event_name, kotlinType(event.payload) });
        try appendFmt(&out, arena, "        sink?.on{s}(payload)\n", .{event_name});
        try out.appendSlice(arena, "    }\n\n");
    }

    try out.appendSlice(arena, "}\n");
    return out.toOwnedSlice(arena);
}

fn renderAndroidJniBridge(arena: std.mem.Allocator, spec: ApiSpec, compat: compatibility.Metadata) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "// Code generated by `wizig codegen`. DO NOT EDIT.\n");
    try out.appendSlice(arena, "#include <jni.h>\n");
    try out.appendSlice(arena, "#include <stdint.h>\n");
    try out.appendSlice(arena, "#include <stdbool.h>\n");
    try out.appendSlice(arena, "#include <stdlib.h>\n");
    try out.appendSlice(arena, "#include <string.h>\n");
    try out.appendSlice(arena, "#include <stdio.h>\n");
    try out.appendSlice(arena, "#include <dlfcn.h>\n");
    try out.appendSlice(arena, "#if defined(__ANDROID__)\n");
    try out.appendSlice(arena, "#include <android/log.h>\n");
    try out.appendSlice(arena, "#include <pthread.h>\n");
    try out.appendSlice(arena, "#include <unistd.h>\n");
    try out.appendSlice(arena, "#endif\n\n");
    try appendFmt(&out, arena, "#define WIZIG_EXPECTED_ABI_VERSION {d}\n", .{compat.abi_version});
    try appendFmt(&out, arena, "#define WIZIG_EXPECTED_CONTRACT_HASH \"{s}\"\n\n", .{compat.contract_hash_hex});
    try out.appendSlice(arena, "extern void wizig_bytes_free(uint8_t* ptr, size_t len);\n");
    try out.appendSlice(arena, "extern uint32_t wizig_ffi_abi_version(void);\n");
    try out.appendSlice(arena, "extern const uint8_t* wizig_ffi_contract_hash_ptr(void);\n");
    try out.appendSlice(arena, "extern size_t wizig_ffi_contract_hash_len(void);\n");
    try out.appendSlice(arena, "extern const uint8_t* wizig_ffi_last_error_domain_ptr(void);\n");
    try out.appendSlice(arena, "extern size_t wizig_ffi_last_error_domain_len(void);\n");
    try out.appendSlice(arena, "extern int32_t wizig_ffi_last_error_code(void);\n");
    try out.appendSlice(arena, "extern const uint8_t* wizig_ffi_last_error_message_ptr(void);\n");
    try out.appendSlice(arena, "extern size_t wizig_ffi_last_error_message_len(void);\n");
    for (spec.methods) |method| {
        const ffi_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});
        try appendFmt(&out, arena, "extern int32_t {s}(", .{ffi_name});
        var need_comma = false;
        switch (method.input) {
            .void => {},
            .string => {
                try out.appendSlice(arena, "const uint8_t* input_ptr, size_t input_len");
                need_comma = true;
            },
            .int => {
                try out.appendSlice(arena, "int64_t input");
                need_comma = true;
            },
            .bool => {
                try out.appendSlice(arena, "uint8_t input");
                need_comma = true;
            },
        }
        switch (method.output) {
            .string => {
                if (need_comma) try out.appendSlice(arena, ", ");
                try out.appendSlice(arena, "uint8_t** out_ptr, size_t* out_len");
            },
            .int => {
                if (need_comma) try out.appendSlice(arena, ", ");
                try out.appendSlice(arena, "int64_t* out_value");
            },
            .bool => {
                if (need_comma) try out.appendSlice(arena, ", ");
                try out.appendSlice(arena, "uint8_t* out_value");
            },
            .void => {},
        }
        try out.appendSlice(arena, ");\n");
    }
    try out.appendSlice(arena, "\n");

    try out.appendSlice(arena, "#if defined(__ANDROID__)\n");
    try out.appendSlice(arena, "static pthread_once_t wizig_stdio_forward_once = PTHREAD_ONCE_INIT;\n\n");
    try out.appendSlice(arena, "static void* wizig_android_stdio_forward_loop(void* ctx) {\n");
    try out.appendSlice(arena, "    int read_fd = *(int*)ctx;\n");
    try out.appendSlice(arena, "    free(ctx);\n");
    try out.appendSlice(arena, "    char buffer[1024];\n");
    try out.appendSlice(arena, "    while (true) {\n");
    try out.appendSlice(arena, "        ssize_t read_count = read(read_fd, buffer, sizeof(buffer) - 1);\n");
    try out.appendSlice(arena, "        if (read_count <= 0) break;\n");
    try out.appendSlice(arena, "        buffer[(size_t)read_count] = '\\0';\n");
    try out.appendSlice(arena, "        __android_log_write(ANDROID_LOG_INFO, \"WizigZig\", buffer);\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    close(read_fd);\n");
    try out.appendSlice(arena, "    return NULL;\n");
    try out.appendSlice(arena, "}\n\n");
    try out.appendSlice(arena, "static void wizig_android_setup_stdio_forwarder(void) {\n");
    try out.appendSlice(arena, "    int pipe_fds[2];\n");
    try out.appendSlice(arena, "    if (pipe(pipe_fds) != 0) return;\n");
    try out.appendSlice(arena, "    const int read_fd = pipe_fds[0];\n");
    try out.appendSlice(arena, "    const int write_fd = pipe_fds[1];\n\n");
    try out.appendSlice(arena, "    if (dup2(write_fd, STDOUT_FILENO) < 0 || dup2(write_fd, STDERR_FILENO) < 0) {\n");
    try out.appendSlice(arena, "        close(read_fd);\n");
    try out.appendSlice(arena, "        close(write_fd);\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    close(write_fd);\n");
    try out.appendSlice(arena, "    setvbuf(stdout, NULL, _IONBF, 0);\n");
    try out.appendSlice(arena, "    setvbuf(stderr, NULL, _IONBF, 0);\n\n");
    try out.appendSlice(arena, "    int* thread_fd = (int*)malloc(sizeof(int));\n");
    try out.appendSlice(arena, "    if (thread_fd == NULL) {\n");
    try out.appendSlice(arena, "        close(read_fd);\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    *thread_fd = read_fd;\n\n");
    try out.appendSlice(arena, "    pthread_t thread;\n");
    try out.appendSlice(arena, "    if (pthread_create(&thread, NULL, wizig_android_stdio_forward_loop, thread_fd) != 0) {\n");
    try out.appendSlice(arena, "        free(thread_fd);\n");
    try out.appendSlice(arena, "        close(read_fd);\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    pthread_detach(thread);\n");
    try out.appendSlice(arena, "}\n\n");
    try out.appendSlice(arena, "static void wizig_forward_stdio_to_logcat_once(void) {\n");
    try out.appendSlice(arena, "    pthread_once(&wizig_stdio_forward_once, wizig_android_setup_stdio_forwarder);\n");
    try out.appendSlice(arena, "}\n");
    try out.appendSlice(arena, "#else\n");
    try out.appendSlice(arena, "static void wizig_forward_stdio_to_logcat_once(void) {\n");
    try out.appendSlice(arena, "}\n");
    try out.appendSlice(arena, "#endif\n\n");

    try out.appendSlice(arena, "static void copy_slice_to_buffer(const uint8_t* ptr, size_t len, char* out, size_t cap) {\n");
    try out.appendSlice(arena, "    if (cap == 0) return;\n");
    try out.appendSlice(arena, "    if (ptr == NULL || len == 0) {\n");
    try out.appendSlice(arena, "        out[0] = '\\0';\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    size_t n = len < (cap - 1) ? len : (cap - 1);\n");
    try out.appendSlice(arena, "    memcpy(out, ptr, n);\n");
    try out.appendSlice(arena, "    out[n] = '\\0';\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static void throw_structured_error(JNIEnv* env, const char* domain, int32_t code, const char* message) {\n");
    try out.appendSlice(arena, "    jclass structured_cls = (*env)->FindClass(env, \"dev/wizig/WizigGeneratedFfiException\");\n");
    try out.appendSlice(arena, "    if (structured_cls != NULL) {\n");
    try out.appendSlice(arena, "        jmethodID ctor = (*env)->GetMethodID(env, structured_cls, \"<init>\", \"(Ljava/lang/String;ILjava/lang/String;)V\");\n");
    try out.appendSlice(arena, "        if (ctor != NULL) {\n");
    try out.appendSlice(arena, "            jstring j_domain = (*env)->NewStringUTF(env, domain != NULL ? domain : \"wizig.runtime\");\n");
    try out.appendSlice(arena, "            jstring j_message = (*env)->NewStringUTF(env, message != NULL ? message : \"wizig ffi error\");\n");
    try out.appendSlice(arena, "            if (j_domain != NULL && j_message != NULL) {\n");
    try out.appendSlice(arena, "                jobject ex = (*env)->NewObject(env, structured_cls, ctor, j_domain, (jint)code, j_message);\n");
    try out.appendSlice(arena, "                if (ex != NULL) {\n");
    try out.appendSlice(arena, "                    (*env)->Throw(env, (jthrowable)ex);\n");
    try out.appendSlice(arena, "                }\n");
    try out.appendSlice(arena, "                (*env)->DeleteLocalRef(env, ex);\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "            (*env)->DeleteLocalRef(env, j_domain);\n");
    try out.appendSlice(arena, "            (*env)->DeleteLocalRef(env, j_message);\n");
    try out.appendSlice(arena, "            return;\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    jclass fallback_cls = (*env)->FindClass(env, \"java/lang/IllegalStateException\");\n");
    try out.appendSlice(arena, "    if (fallback_cls == NULL) return;\n");
    try out.appendSlice(arena, "    char buffer[320];\n");
    try out.appendSlice(arena, "    snprintf(buffer, sizeof(buffer), \"%s[%d]: %s\", domain != NULL ? domain : \"wizig.runtime\", (int)code, message != NULL ? message : \"wizig ffi error\");\n");
    try out.appendSlice(arena, "    (*env)->ThrowNew(env, fallback_cls, buffer);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static void throw_status_error(JNIEnv* env, const char* function_name, int32_t status) {\n");
    try out.appendSlice(arena, "    const uint8_t* domain_ptr = wizig_ffi_last_error_domain_ptr();\n");
    try out.appendSlice(arena, "    size_t domain_len = wizig_ffi_last_error_domain_len();\n");
    try out.appendSlice(arena, "    int32_t code = wizig_ffi_last_error_code();\n");
    try out.appendSlice(arena, "    const uint8_t* message_ptr = wizig_ffi_last_error_message_ptr();\n");
    try out.appendSlice(arena, "    size_t message_len = wizig_ffi_last_error_message_len();\n");
    try out.appendSlice(arena, "    char domain[96];\n");
    try out.appendSlice(arena, "    char message[256];\n");
    try out.appendSlice(arena, "    copy_slice_to_buffer(domain_ptr, domain_len, domain, sizeof(domain));\n");
    try out.appendSlice(arena, "    copy_slice_to_buffer(message_ptr, message_len, message, sizeof(message));\n");
    try out.appendSlice(arena, "    if (domain[0] == '\\0') snprintf(domain, sizeof(domain), \"%s\", \"wizig.runtime\");\n");
    try out.appendSlice(arena, "    if (message[0] == '\\0') snprintf(message, sizeof(message), \"%s failed with status %d\", function_name, (int)status);\n");
    try out.appendSlice(arena, "    throw_structured_error(env, domain, code == 0 ? status : code, message);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static jstring new_jstring_from_bytes(JNIEnv* env, const uint8_t* bytes, size_t len) {\n");
    try out.appendSlice(arena, "    char* tmp = (char*)malloc(len + 1);\n");
    try out.appendSlice(arena, "    if (tmp == NULL) {\n");
    try out.appendSlice(arena, "        throw_structured_error(env, \"wizig.memory\", 2, \"wizig generated bridge out of memory\");\n");
    try out.appendSlice(arena, "        return NULL;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    if (len > 0) memcpy(tmp, bytes, len);\n");
    try out.appendSlice(arena, "    tmp[len] = '\\0';\n");
    try out.appendSlice(arena, "    jstring result = (*env)->NewStringUTF(env, tmp);\n");
    try out.appendSlice(arena, "    free(tmp);\n");
    try out.appendSlice(arena, "    return result;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static int ensure_symbol(JNIEnv* env, const char* symbol_name) {\n");
    try out.appendSlice(arena, "    void* symbol = dlsym(RTLD_DEFAULT, symbol_name);\n");
    try out.appendSlice(arena, "    if (symbol != NULL) return 1;\n");
    try out.appendSlice(arena, "    char message[256];\n");
    try out.appendSlice(arena, "    snprintf(message, sizeof(message), \"missing Wizig FFI symbol: %s\", symbol_name);\n");
    try out.appendSlice(arena, "    throw_structured_error(env, \"wizig.compatibility\", 1001, message);\n");
    try out.appendSlice(arena, "    return 0;\n");
    try out.appendSlice(arena, "}\n\n");

    const validate_jni_name = try jniEscape(arena, "wizig_validate_bindings");
    try appendFmt(
        &out,
        arena,
        "JNIEXPORT void JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_{s}(JNIEnv* env, jclass clazz) {{\n",
        .{validate_jni_name},
    );
    try out.appendSlice(arena, "    (void)clazz;\n");
    try out.appendSlice(arena, "    wizig_forward_stdio_to_logcat_once();\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_bytes_free\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_abi_version\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_contract_hash_ptr\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_contract_hash_len\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_domain_ptr\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_domain_len\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_code\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_message_ptr\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_message_len\")) return;\n");
    for (spec.methods) |method| {
        try appendFmt(&out, arena, "    if (!ensure_symbol(env, \"wizig_api_{s}\")) return;\n", .{method.name});
    }
    try out.appendSlice(arena, "    uint32_t actual_abi = wizig_ffi_abi_version();\n");
    try out.appendSlice(arena, "    const uint8_t* actual_hash_ptr = wizig_ffi_contract_hash_ptr();\n");
    try out.appendSlice(arena, "    size_t actual_hash_len = wizig_ffi_contract_hash_len();\n");
    try out.appendSlice(arena, "    char actual_hash[96];\n");
    try out.appendSlice(arena, "    copy_slice_to_buffer(actual_hash_ptr, actual_hash_len, actual_hash, sizeof(actual_hash));\n");
    try out.appendSlice(arena, "    if (actual_abi != WIZIG_EXPECTED_ABI_VERSION || strcmp(actual_hash, WIZIG_EXPECTED_CONTRACT_HASH) != 0) {\n");
    try out.appendSlice(arena, "        char message[320];\n");
    try out.appendSlice(arena, "        snprintf(message, sizeof(message), \"ffi compatibility mismatch: expected abi=%u hash=%s got abi=%u hash=%s\", (unsigned)WIZIG_EXPECTED_ABI_VERSION, WIZIG_EXPECTED_CONTRACT_HASH, (unsigned)actual_abi, actual_hash);\n");
    try out.appendSlice(arena, "        throw_structured_error(env, \"wizig.compatibility\", 1002, message);\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "}\n\n");

    for (spec.methods) |method| {
        const ffi_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});
        const jni_name = try jniEscape(arena, ffi_name);
        try appendFmt(
            &out,
            arena,
            "JNIEXPORT {s} JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_{s}(JNIEnv* env, jclass clazz",
            .{ jniCType(method.output), jni_name },
        );
        switch (method.input) {
            .void => {},
            .string => try out.appendSlice(arena, ", jstring input"),
            .int => try out.appendSlice(arena, ", jlong input"),
            .bool => try out.appendSlice(arena, ", jboolean input"),
        }
        try out.appendSlice(arena, ") {\n");
        try out.appendSlice(arena, "    (void)clazz;\n");

        switch (method.output) {
            .string => {
                try out.appendSlice(arena, "    uint8_t* out_ptr = NULL;\n");
                try out.appendSlice(arena, "    size_t out_len = 0;\n");
                switch (method.input) {
                    .void => try appendFmt(&out, arena, "    int32_t status = {s}(&out_ptr, &out_len);\n", .{ffi_name}),
                    .string => {
                        try out.appendSlice(arena, "    if (input == NULL) {\n");
                        try appendFmt(&out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
                        try out.appendSlice(arena, "        return NULL;\n");
                        try out.appendSlice(arena, "    }\n");
                        try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
                        try out.appendSlice(arena, "    if (input_utf == NULL) return NULL;\n");
                        try appendFmt(&out, arena, "    int32_t status = {s}((const uint8_t*)input_utf, strlen(input_utf), &out_ptr, &out_len);\n", .{ffi_name});
                        try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
                    },
                    .int => try appendFmt(&out, arena, "    int32_t status = {s}((int64_t)input, &out_ptr, &out_len);\n", .{ffi_name}),
                    .bool => try appendFmt(&out, arena, "    int32_t status = {s}(input ? 1 : 0, &out_ptr, &out_len);\n", .{ffi_name}),
                }
                try out.appendSlice(arena, "    if (status != 0) {\n");
                try appendFmt(&out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
                try out.appendSlice(arena, "        if (out_ptr != NULL) wizig_bytes_free(out_ptr, out_len);\n");
                try out.appendSlice(arena, "        return NULL;\n");
                try out.appendSlice(arena, "    }\n");
                try out.appendSlice(arena, "    if (out_ptr == NULL) {\n");
                try appendFmt(&out, arena, "        throw_structured_error(env, \"wizig.runtime\", 255, \"{s} returned null output\");\n", .{ffi_name});
                try out.appendSlice(arena, "        return NULL;\n");
                try out.appendSlice(arena, "    }\n");
                try out.appendSlice(arena, "    jstring result = new_jstring_from_bytes(env, out_ptr, out_len);\n");
                try out.appendSlice(arena, "    wizig_bytes_free(out_ptr, out_len);\n");
                try out.appendSlice(arena, "    return result;\n");
            },
            .int => {
                try out.appendSlice(arena, "    int64_t out_value = 0;\n");
                switch (method.input) {
                    .void => try appendFmt(&out, arena, "    int32_t status = {s}(&out_value);\n", .{ffi_name}),
                    .string => {
                        try out.appendSlice(arena, "    if (input == NULL) {\n");
                        try appendFmt(&out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
                        try out.appendSlice(arena, "        return 0;\n");
                        try out.appendSlice(arena, "    }\n");
                        try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
                        try out.appendSlice(arena, "    if (input_utf == NULL) return 0;\n");
                        try appendFmt(&out, arena, "    int32_t status = {s}((const uint8_t*)input_utf, strlen(input_utf), &out_value);\n", .{ffi_name});
                        try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
                    },
                    .int => try appendFmt(&out, arena, "    int32_t status = {s}((int64_t)input, &out_value);\n", .{ffi_name}),
                    .bool => try appendFmt(&out, arena, "    int32_t status = {s}(input ? 1 : 0, &out_value);\n", .{ffi_name}),
                }
                try out.appendSlice(arena, "    if (status != 0) {\n");
                try appendFmt(&out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
                try out.appendSlice(arena, "        return 0;\n");
                try out.appendSlice(arena, "    }\n");
                try out.appendSlice(arena, "    return (jlong)out_value;\n");
            },
            .bool => {
                try out.appendSlice(arena, "    uint8_t out_value = 0;\n");
                switch (method.input) {
                    .void => try appendFmt(&out, arena, "    int32_t status = {s}(&out_value);\n", .{ffi_name}),
                    .string => {
                        try out.appendSlice(arena, "    if (input == NULL) {\n");
                        try appendFmt(&out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
                        try out.appendSlice(arena, "        return JNI_FALSE;\n");
                        try out.appendSlice(arena, "    }\n");
                        try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
                        try out.appendSlice(arena, "    if (input_utf == NULL) return JNI_FALSE;\n");
                        try appendFmt(&out, arena, "    int32_t status = {s}((const uint8_t*)input_utf, strlen(input_utf), &out_value);\n", .{ffi_name});
                        try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
                    },
                    .int => try appendFmt(&out, arena, "    int32_t status = {s}((int64_t)input, &out_value);\n", .{ffi_name}),
                    .bool => try appendFmt(&out, arena, "    int32_t status = {s}(input ? 1 : 0, &out_value);\n", .{ffi_name}),
                }
                try out.appendSlice(arena, "    if (status != 0) {\n");
                try appendFmt(&out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
                try out.appendSlice(arena, "        return JNI_FALSE;\n");
                try out.appendSlice(arena, "    }\n");
                try out.appendSlice(arena, "    return out_value ? JNI_TRUE : JNI_FALSE;\n");
            },
            .void => {
                switch (method.input) {
                    .void => try appendFmt(&out, arena, "    int32_t status = {s}();\n", .{ffi_name}),
                    .string => {
                        try out.appendSlice(arena, "    if (input == NULL) {\n");
                        try appendFmt(&out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
                        try out.appendSlice(arena, "        return;\n");
                        try out.appendSlice(arena, "    }\n");
                        try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
                        try out.appendSlice(arena, "    if (input_utf == NULL) return;\n");
                        try appendFmt(&out, arena, "    int32_t status = {s}((const uint8_t*)input_utf, strlen(input_utf));\n", .{ffi_name});
                        try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
                    },
                    .int => try appendFmt(&out, arena, "    int32_t status = {s}((int64_t)input);\n", .{ffi_name}),
                    .bool => try appendFmt(&out, arena, "    int32_t status = {s}(input ? 1 : 0);\n", .{ffi_name}),
                }
                try out.appendSlice(arena, "    if (status != 0) {\n");
                try appendFmt(&out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
                try out.appendSlice(arena, "    }\n");
            },
        }
        try out.appendSlice(arena, "}\n\n");
    }

    return out.toOwnedSlice(arena);
}

fn renderAndroidJniCmake(arena: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(
        arena,
        "cmake_minimum_required(VERSION 3.22.1)\n" ++
            "project(wizig_generated_jni C)\n\n" ++
            "add_library(wizigffi SHARED IMPORTED)\n" ++
            "set_target_properties(wizigffi PROPERTIES\n" ++
            "    IMPORTED_LOCATION \"${{CMAKE_CURRENT_LIST_DIR}}/../jniLibs/${{ANDROID_ABI}}/libwizigffi.so\"\n" ++
            ")\n\n" ++
            "add_library(wizigjni SHARED WizigGeneratedApiBridge.c)\n" ++
            "target_link_libraries(wizigjni wizigffi log dl)\n",
        .{},
    );
}

fn zigType(value: ApiType) []const u8 {
    return switch (value) {
        .string => "[]const u8",
        .int => "i64",
        .bool => "bool",
        .void => "void",
    };
}

fn swiftType(value: ApiType) []const u8 {
    return switch (value) {
        .string => "String",
        .int => "Int64",
        .bool => "Bool",
        .void => "Void",
    };
}

fn kotlinType(value: ApiType) []const u8 {
    return switch (value) {
        .string => "String",
        .int => "Long",
        .bool => "Boolean",
        .void => "Unit",
    };
}

fn jniCType(value: ApiType) []const u8 {
    return switch (value) {
        .string => "jstring",
        .int => "jlong",
        .bool => "jboolean",
        .void => "void",
    };
}

fn zigDefaultValue(value: ApiType) []const u8 {
    return switch (value) {
        .string => "\"\"",
        .int => "0",
        .bool => "false",
        .void => "{}",
    };
}

fn swiftDefaultValue(value: ApiType) []const u8 {
    return switch (value) {
        .string => "\"\"",
        .int => "0",
        .bool => "false",
        .void => "()",
    };
}

fn kotlinDefaultValue(value: ApiType) []const u8 {
    return switch (value) {
        .string => "\"\"",
        .int => "0L",
        .bool => "false",
        .void => "Unit",
    };
}

fn jniEscape(arena: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);
    for (input) |ch| {
        switch (ch) {
            '_' => try out.appendSlice(arena, "_1"),
            ';' => try out.appendSlice(arena, "_2"),
            '[' => try out.appendSlice(arena, "_3"),
            else => try out.append(arena, ch),
        }
    }
    return out.toOwnedSlice(arena);
}

fn upperCamel(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var uppercase_next = true;
    for (input) |ch| {
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch))) {
            uppercase_next = true;
            continue;
        }
        if (uppercase_next) {
            try out.append(allocator, std.ascii.toUpper(ch));
        } else {
            try out.append(allocator, ch);
        }
        uppercase_next = false;
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "Event");
    }

    return out.toOwnedSlice(allocator);
}

fn appendFmt(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const rendered = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(rendered);
    try out.appendSlice(allocator, rendered);
}

fn lessString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

test "renderZigFfiRoot emits compatibility handshake and structured error symbols" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var methods = [_]ApiMethod{
        .{ .name = "echo", .input = .string, .output = .string },
        .{ .name = "uptime", .input = .void, .output = .int },
    };
    var events = [_]ApiEvent{
        .{ .name = "log", .payload = .string },
    };
    const spec: ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = methods[0..],
        .events = events[0..],
    };

    const compat_meta = try compatibility.buildMetadata(arena, spec.namespace, spec.methods, spec.events);
    const rendered = try renderZigFfiRoot(arena, spec, compat_meta);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_ffi_abi_version() u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_ffi_contract_hash_ptr() [*]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_ffi_last_error_domain_ptr() [*]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_ffi_last_error_code() i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "fn setLastError(domain: ErrorDomain, code: i32, message: []const u8) i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, compat_meta.contract_hash_hex) != null);
}

test "renderSwiftApi emits compatibility checks and structured ffi error mapping" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var methods = [_]ApiMethod{
        .{ .name = "echo", .input = .string, .output = .string },
    };
    var events = [_]ApiEvent{
        .{ .name = "log", .payload = .string },
    };
    const spec: ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = methods[0..],
        .events = events[0..],
    };

    const compat_meta = try compatibility.buildMetadata(arena, spec.namespace, spec.methods, spec.events);
    const rendered = try renderSwiftApi(arena, spec, compat_meta);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "case compatibilityMismatch(expectedAbi: UInt32, actualAbi: UInt32, expectedContractHash: String, actualContractHash: String)") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "case ffiCallFailed(function: String, domain: String, code: Int32, message: String)") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "wizig_ffi_last_error_domain_ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "wizig_ffi_last_error_message_ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "func readLastError() -> (domain: String, code: Int32, message: String)") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, compat_meta.contract_hash_hex) != null);
}

test "renderKotlinApi and renderAndroidJniBridge emit compatibility and structured errors" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var methods = [_]ApiMethod{
        .{ .name = "echo", .input = .string, .output = .string },
    };
    var events = [_]ApiEvent{
        .{ .name = "log", .payload = .string },
    };
    const spec: ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = methods[0..],
        .events = events[0..],
    };

    const compat_meta = try compatibility.buildMetadata(arena, spec.namespace, spec.methods, spec.events);
    const kotlin_rendered = try renderKotlinApi(arena, spec, compat_meta);

    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "private const val WIZIG_EXPECTED_ABI_VERSION: Int =") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "private const val WIZIG_EXPECTED_CONTRACT_HASH: String =") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "class WizigGeneratedFfiException(") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, compat_meta.contract_hash_hex) != null);

    const jni_rendered = try renderAndroidJniBridge(arena, spec, compat_meta);

    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "extern uint32_t wizig_ffi_abi_version(void);") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "extern const uint8_t* wizig_ffi_last_error_domain_ptr(void);") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "throw_structured_error(env, \"wizig.compatibility\", 1002, message);") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "ffi compatibility mismatch: expected abi=%u hash=%s got abi=%u hash=%s") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "#include <android/log.h>") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "static void wizig_forward_stdio_to_logcat_once(void)") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "wizig_forward_stdio_to_logcat_once();") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, compat_meta.contract_hash_hex) != null);
}
