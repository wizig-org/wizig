//! Project scaffolding for `wizig create`.
const std = @import("std");
const Io = std.Io;
const fs_util = @import("../../support/fs.zig");
const sdk_locator = @import("../../support/sdk_locator.zig");
const codegen_cmd = @import("../codegen/root.zig");

/// Errors emitted by scaffolding helpers.
pub const CreateError = error{CreateFailed};
/// Platform selection for generated hosts.
pub const CreatePlatforms = struct {
    ios: bool = true,
    android: bool = true,
    macos: bool = false,
};

/// Creates a full Wizig application scaffold at `destination_dir_raw`.
pub fn createApp(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    platforms: CreatePlatforms,
    explicit_sdk_root: ?[]const u8,
    force_host_overwrite: bool,
) !void {
    if (!hasAnyPlatform(platforms)) {
        try stderr.writeAll("error: at least one platform must be selected\n");
        try stderr.flush();
        return error.CreateFailed;
    }

    const app_name = try sanitizeProjectName(arena, app_name_raw);
    const app_identifier = try toIdentifierLower(arena, app_name);
    const destination_dir = destination_dir_raw;

    std.Io.Dir.cwd().createDirPath(io, destination_dir) catch |err| {
        try stderr.print("error: failed to create destination '{s}': {s}\n", .{ destination_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const resolved = sdk_locator.resolve(arena, io, parent_environ_map, stderr, explicit_sdk_root) catch {
        try stderr.flush();
        return error.CreateFailed;
    };

    const dot_wizig_dir = try joinPath(arena, destination_dir, ".wizig");
    const lib_dir = try joinPath(arena, destination_dir, "lib");
    const plugins_dir = try joinPath(arena, destination_dir, "plugins");
    const app_sdk_dir = try joinPath(arena, dot_wizig_dir, "sdk");
    const app_runtime_dir = try joinPath(arena, dot_wizig_dir, "runtime");
    const app_generated_dir = try joinPath(arena, dot_wizig_dir, "generated");
    const app_generated_swift_dir = try joinPath(arena, app_generated_dir, "swift");
    const app_generated_kotlin_dir = try joinPath(arena, app_generated_dir, "kotlin");
    const app_generated_zig_dir = try joinPath(arena, app_generated_dir, "zig");
    const app_generated_android_dir = try joinPath(arena, app_generated_dir, "android");
    const app_generated_android_jnilibs_dir = try joinPath(arena, app_generated_android_dir, "jniLibs");
    const app_plugins_meta_dir = try joinPath(arena, dot_wizig_dir, "plugins");

    for (&[_][]const u8{
        lib_dir,
        plugins_dir,
        app_sdk_dir,
        app_runtime_dir,
        app_generated_dir,
        app_generated_swift_dir,
        app_generated_kotlin_dir,
        app_generated_zig_dir,
        app_generated_android_dir,
        app_generated_android_jnilibs_dir,
        app_plugins_meta_dir,
    }) |dir_path| {
        std.Io.Dir.cwd().createDirPath(io, dir_path) catch |err| {
            try stderr.print("error: failed to create '{s}': {s}\n", .{ dir_path, @errorName(err) });
            try stderr.flush();
            return error.CreateFailed;
        };
    }
    try writeFileAtomically(io, try joinPath(arena, app_generated_android_jnilibs_dir, ".gitkeep"), "");

    fs_util.removeTreeIfExists(io, app_sdk_dir) catch {};
    fs_util.removeTreeIfExists(io, app_runtime_dir) catch {};

    fs_util.copyTree(arena, io, resolved.sdk_dir, app_sdk_dir) catch |err| {
        try stderr.print("error: failed to copy SDK into app (.wizig/sdk): {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };
    fs_util.copyTree(arena, io, resolved.runtime_dir, app_runtime_dir) catch |err| {
        try stderr.print("error: failed to copy runtime into app (.wizig/runtime): {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    const template_tokens = [_]fs_util.RenderToken{
        .{ .key = "APP_NAME", .value = app_name },
        .{ .key = "APP_IDENTIFIER", .value = app_identifier },
        .{ .key = "APP_TYPE_NAME", .value = try toSwiftTypeName(arena, app_name) },
    };

    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/.gitignore", try joinPath(arena, destination_dir, ".gitignore"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/README.md", try joinPath(arena, destination_dir, "README.md"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/wizig.yaml", try joinPath(arena, destination_dir, "wizig.yaml"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/lib/main.zig", try joinPath(arena, lib_dir, "main.zig"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/plugins/README.md", try joinPath(arena, plugins_dir, "README.md"), &template_tokens);

    if (platforms.ios) {
        const ios_dir = try joinPath(arena, destination_dir, "ios");
        createIos(arena, io, stderr, stdout, resolved.templates_dir, app_name, ios_dir, force_host_overwrite) catch return error.CreateFailed;
    }
    if (platforms.android) {
        const android_dir = try joinPath(arena, destination_dir, "android");
        createAndroid(
            arena,
            io,
            parent_environ_map,
            stderr,
            stdout,
            resolved.templates_dir,
            app_name,
            android_dir,
            force_host_overwrite,
        ) catch return error.CreateFailed;
    }
    if (platforms.macos) {
        const macos_dir = try joinPath(arena, destination_dir, "macos");
        std.Io.Dir.cwd().createDirPath(io, macos_dir) catch |err| {
            try stderr.print("error: failed to create macOS dir '{s}': {s}\n", .{ macos_dir, @errorName(err) });
            try stderr.flush();
            return error.CreateFailed;
        };
        const macos_readme_path = try joinPath(arena, macos_dir, "README.md");
        try writeFileAtomically(
            io,
            macos_readme_path,
            "# macOS (placeholder)\n\nDesktop scaffolding will be added in a future Wizig release.\n",
        );
    }

    _ = codegen_cmd.ensureProjectGenerated(arena, io, stderr, stdout, destination_dir, null, .{
        .force = true,
    }) catch |err| {
        try stderr.print("error: failed to run initial codegen: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    try stdout.print("created Wizig app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.flush();
}

/// Creates the iOS host scaffold from bundled templates.
pub fn createIos(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    templates_root: []const u8,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    force_host_overwrite: bool,
) !void {
    const app_name = try sanitizeProjectName(arena, app_name_raw);
    const destination_dir = destination_dir_raw;

    std.Io.Dir.cwd().createDirPath(io, destination_dir) catch |err| {
        try stderr.print("error: failed to create destination '{s}': {s}\n", .{ destination_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const tokens = [_]fs_util.RenderToken{
        .{ .key = "APP_NAME", .value = app_name },
        .{ .key = "APP_IDENTIFIER", .value = try toIdentifierLower(arena, app_name) },
        .{ .key = "APP_TYPE_NAME", .value = try toSwiftTypeName(arena, app_name) },
        .{ .key = "ANDROID_PACKAGE", .value = "" },
    };

    const template_dir = try joinPath(arena, templates_root, "app/ios");
    const path_tokens = [_]PathToken{
        .{ .key = "__APP_NAME__", .value = app_name },
    };
    copyTemplateTreeRendered(
        arena,
        io,
        template_dir,
        destination_dir,
        &tokens,
        &path_tokens,
        force_host_overwrite,
    ) catch |err| {
        try stderr.print("error: failed to scaffold iOS host from templates: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    try stdout.print("created iOS app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.print(
        "next: xcodebuild -project {s}/{s}.xcodeproj -scheme {s} -destination 'generic/platform=iOS Simulator' build\n",
        .{ destination_dir, app_name, app_name },
    );
    try stdout.flush();
}

fn renderTemplateToPath(
    arena: std.mem.Allocator,
    io: std.Io,
    templates_root: []const u8,
    template_rel: []const u8,
    output_path: []const u8,
    tokens: []const fs_util.RenderToken,
) !void {
    const template = try fs_util.readTemplate(arena, io, templates_root, template_rel);
    const rendered = try fs_util.renderTemplate(arena, template, tokens);
    try fs_util.writeFileAtomically(io, output_path, rendered);
}
/// Creates the Android host scaffold and initializes Gradle wrapper files.
pub fn createAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    templates_root: []const u8,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    force_host_overwrite: bool,
) !void {
    const app_name = try sanitizeProjectName(arena, app_name_raw);
    const app_type_name = try toSwiftTypeName(arena, app_name);
    const app_identifier = try toIdentifierLower(arena, app_name);
    const destination_dir = destination_dir_raw;
    const package_segment = try sanitizePackageSegment(arena, app_name);
    const package_name = try std.fmt.allocPrint(arena, "dev.wizig.{s}", .{package_segment});
    const package_path = try packageNameToPath(arena, package_name);
    const package_path_forward = try toForwardSlashes(arena, package_path);

    std.Io.Dir.cwd().createDirPath(io, destination_dir) catch |err| {
        try stderr.print("error: failed to create destination '{s}': {s}\n", .{ destination_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const tokens = [_]fs_util.RenderToken{
        .{ .key = "APP_NAME", .value = app_name },
        .{ .key = "APP_IDENTIFIER", .value = app_identifier },
        .{ .key = "APP_TYPE_NAME", .value = app_type_name },
        .{ .key = "ANDROID_PACKAGE", .value = package_name },
    };
    const path_tokens = [_]PathToken{
        .{ .key = "__ANDROID_PACKAGE_PATH__", .value = package_path_forward },
    };

    const template_dir = try joinPath(arena, templates_root, "app/android");
    copyTemplateTreeRendered(
        arena,
        io,
        template_dir,
        destination_dir,
        &tokens,
        &path_tokens,
        force_host_overwrite,
    ) catch |err| {
        try stderr.print("error: failed to scaffold Android host from templates: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    const sdk_dir = parent_environ_map.get("ANDROID_SDK_ROOT") orelse parent_environ_map.get("ANDROID_HOME");
    if (sdk_dir != null and (force_host_overwrite or !fs_util.pathExists(io, try joinPath(arena, destination_dir, "local.properties")))) {
        const local_properties_path = try joinPath(arena, destination_dir, "local.properties");
        const escaped_sdk = try escapeLocalPropertiesValue(arena, sdk_dir.?);
        const local_properties_contents = try std.fmt.allocPrint(arena, "sdk.dir={s}\n", .{escaped_sdk});
        try writeFileAtomically(io, local_properties_path, local_properties_contents);
    }

    const gradlew_path = try joinPath(arena, destination_dir, "gradlew");
    if (fs_util.pathExists(io, gradlew_path)) {
        runCommand(arena, io, stderr, ".", &.{ "chmod", "+x", gradlew_path }, null) catch {};
    }

    try stdout.print("created Android app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.print("next: (cd {s} && ./gradlew :app:assembleDebug)\n", .{destination_dir});
    try stdout.flush();
}

const PathToken = struct {
    key: []const u8,
    value: []const u8,
};

fn copyTemplateTreeRendered(
    arena: std.mem.Allocator,
    io: std.Io,
    src_root: []const u8,
    dst_root: []const u8,
    tokens: []const fs_util.RenderToken,
    path_tokens: []const PathToken,
    force_overwrite: bool,
) !void {
    var src_dir = try std.Io.Dir.cwd().openDir(io, src_root, .{ .iterate = true });
    defer src_dir.close(io);

    try std.Io.Dir.cwd().createDirPath(io, dst_root);
    var walker = try src_dir.walk(arena);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (shouldSkipTemplateEntry(entry.path)) continue;

        const rendered_rel = try renderPathTokens(arena, entry.path, path_tokens);
        const src_path = try joinPath(arena, src_root, entry.path);
        const dst_path = try joinPath(arena, dst_root, rendered_rel);

        switch (entry.kind) {
            .directory => try std.Io.Dir.cwd().createDirPath(io, dst_path),
            .file => {
                if (!force_overwrite and fs_util.pathExists(io, dst_path)) {
                    continue;
                }

                const bytes = try std.Io.Dir.cwd().readFileAlloc(io, src_path, arena, .limited(256 * 1024 * 1024));
                if (isTemplateTextFile(src_path, bytes)) {
                    const rendered = try fs_util.renderTemplate(arena, bytes, tokens);
                    try fs_util.writeFileAtomically(io, dst_path, rendered);
                } else {
                    try fs_util.writeFileAtomically(io, dst_path, bytes);
                }
            },
            else => {},
        }
    }
}

fn renderPathTokens(allocator: std.mem.Allocator, raw_path: []const u8, path_tokens: []const PathToken) ![]u8 {
    var rendered = try allocator.dupe(u8, raw_path);
    for (path_tokens) |token| {
        rendered = try replaceAllAlloc(allocator, rendered, token.key, token.value);
    }
    return rendered;
}

fn replaceAllAlloc(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, haystack);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, cursor, needle)) |idx| {
        try out.appendSlice(allocator, haystack[cursor..idx]);
        try out.appendSlice(allocator, replacement);
        cursor = idx + needle.len;
    }
    try out.appendSlice(allocator, haystack[cursor..]);
    return out.toOwnedSlice(allocator);
}

fn isTemplateTextFile(path: []const u8, bytes: []const u8) bool {
    const basename = std.fs.path.basename(path);
    if (std.mem.eql(u8, basename, "gradlew") or std.mem.eql(u8, basename, "gradlew.bat")) {
        return true;
    }

    const ext = std.fs.path.extension(path);
    for (template_text_extensions) |text_ext| {
        if (std.mem.eql(u8, ext, text_ext)) return true;
    }

    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return false;
    return std.unicode.utf8ValidateSlice(bytes);
}

fn shouldSkipTemplateEntry(entry_path: []const u8) bool {
    var it = std.mem.splitAny(u8, entry_path, "/\\");
    while (it.next()) |segment| {
        if (segment.len == 0) continue;
        if (std.mem.eql(u8, segment, "project.yml")) return true;
        if (std.mem.eql(u8, segment, "Sources")) return true;
        if (std.mem.eql(u8, segment, ".DS_Store")) return true;
        if (std.mem.eql(u8, segment, ".gradle")) return true;
        if (std.mem.eql(u8, segment, ".idea")) return true;
        if (std.mem.eql(u8, segment, "build")) return true;
    }
    return false;
}

const template_text_extensions = [_][]const u8{
    ".swift",
    ".pbxproj",
    ".plist",
    ".xcworkspacedata",
    ".kts",
    ".gradle",
    ".xml",
    ".kt",
    ".java",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".properties",
    ".md",
    ".txt",
    ".gitignore",
    ".pro",
};

fn hasAnyPlatform(platforms: CreatePlatforms) bool {
    return platforms.ios or platforms.android or platforms.macos;
}

fn runCommand(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    cwd_path: []const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !void {
    const result = std.process.run(arena, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd_path },
        .environ_map = environ_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch |err| {
        try stderr.print("error: failed to spawn '{s}': {s}\n", .{ argv[0], @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const success = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };

    if (!success) {
        if (result.stdout.len > 0) {
            try stderr.print("{s}\n", .{result.stdout});
        }
        if (result.stderr.len > 0) {
            try stderr.print("{s}\n", .{result.stderr});
        }
        try stderr.flush();
        return error.CreateFailed;
    }
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

fn sanitizeProjectName(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (raw_name) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_') {
            try out.append(allocator, ch);
        } else if (ch == ' ') {
            try out.append(allocator, '-');
        }
    }

    const value = try out.toOwnedSlice(allocator);
    if (value.len == 0) return error.CreateFailed;
    return value;
}

fn toIdentifierLower(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (raw_name) |ch| {
        if (std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch)) {
            try out.append(allocator, std.ascii.toLower(ch));
        }
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "app");
    }

    if (std.ascii.isDigit(out.items[0])) {
        try out.insertSlice(allocator, 0, "app");
    }

    return out.toOwnedSlice(allocator);
}

fn sanitizePackageSegment(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (raw_name) |ch| {
        if (std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch)) {
            try out.append(allocator, std.ascii.toLower(ch));
        } else if (ch == '-' or ch == '_' or ch == ' ') {
            if (out.items.len == 0 or out.items[out.items.len - 1] == '_') continue;
            try out.append(allocator, '_');
        }
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "app");
    }

    if (std.ascii.isDigit(out.items[0])) {
        try out.insertSlice(allocator, 0, "app_");
    }

    return out.toOwnedSlice(allocator);
}

fn packageNameToPath(allocator: std.mem.Allocator, package_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (package_name) |ch| {
        if (ch == '.') {
            try out.append(allocator, std.fs.path.sep);
            continue;
        }
        try out.append(allocator, ch);
    }

    return out.toOwnedSlice(allocator);
}

fn toForwardSlashes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, input);
    for (out) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
    return out;
}

fn escapeLocalPropertiesValue(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (input) |ch| {
        if (ch == '\\') {
            try out.appendSlice(allocator, "\\\\");
            continue;
        }
        try out.append(allocator, ch);
    }
    return out.toOwnedSlice(allocator);
}

fn toSwiftTypeName(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var uppercase_next = true;
    for (raw_name) |ch| {
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch))) {
            uppercase_next = true;
            continue;
        }

        if (out.items.len == 0 and std.ascii.isDigit(ch)) {
            try out.append(allocator, 'A');
        }

        if (uppercase_next and std.ascii.isAlphabetic(ch)) {
            try out.append(allocator, std.ascii.toUpper(ch));
        } else {
            try out.append(allocator, ch);
        }
        uppercase_next = false;
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "WizigApp");
    }

    return out.toOwnedSlice(allocator);
}

test "sanitizeProjectName keeps safe characters" {
    const got = try sanitizeProjectName(std.testing.allocator, "My App!@# 123");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("My-App-123", got);
}

test "sanitizePackageSegment produces valid lowercase token" {
    const got = try sanitizePackageSegment(std.testing.allocator, "123 Hello-World");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("app_123_hello_world", got);
}

test "packageNameToPath converts dots to separators" {
    const got = try packageNameToPath(std.testing.allocator, "dev.wizig.demo");
    defer std.testing.allocator.free(got);
    try std.testing.expect(std.mem.indexOfScalar(u8, got, '.') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, got, std.fs.path.sep) != null);
}

test "toSwiftTypeName strips separators and capitalizes words" {
    const got = try toSwiftTypeName(std.testing.allocator, "my-cool_app");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("MyCoolApp", got);
}

test "escapeLocalPropertiesValue escapes backslashes" {
    const got = try escapeLocalPropertiesValue(std.testing.allocator, "C:\\Users\\wizig\\sdk");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("C:\\\\Users\\\\wizig\\\\sdk", got);
}
