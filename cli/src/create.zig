const std = @import("std");
const Io = std.Io;

pub const CreateError = error{CreateFailed};

pub fn createIos(
    arena: std.mem.Allocator,
    io: std.Io,
    _: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
) !void {
    const app_name = try sanitizeProjectName(arena, app_name_raw);
    const app_type_name = try toSwiftTypeName(arena, app_name);
    const destination_dir = destination_dir_raw;

    std.Io.Dir.cwd().createDirPath(io, destination_dir) catch |err| {
        try stderr.print("error: failed to create destination '{s}': {s}\n", .{ destination_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const sources_dir = try joinPath(arena, destination_dir, "Sources");
    std.Io.Dir.cwd().createDirPath(io, sources_dir) catch |err| {
        try stderr.print("error: failed to create sources dir '{s}': {s}\n", .{ sources_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const cwd_abs = try std.process.currentPathAlloc(io, arena);
    const sdk_ios_abs = try std.fs.path.resolve(arena, &.{ cwd_abs, "sdk/ios" });
    const normalized_sdk_path = sdk_ios_abs;

    const project_yml_path = try joinPath(arena, destination_dir, "project.yml");
    const app_swift_path = try joinPath(arena, sources_dir, "App.swift");

    const project_yml_contents = try std.fmt.allocPrint(
        arena,
        "name: {s}\n" ++
            "options:\n" ++
            "  bundleIdPrefix: dev.ziggy.app\n" ++
            "settings:\n" ++
            "  base:\n" ++
            "    SWIFT_VERSION: 6.0\n" ++
            "packages:\n" ++
            "  Ziggy:\n" ++
            "    path: {s}\n" ++
            "targets:\n" ++
            "  {s}:\n" ++
            "    type: application\n" ++
            "    platform: iOS\n" ++
            "    deploymentTarget: \"16.0\"\n" ++
            "    sources:\n" ++
            "      - Sources\n" ++
            "    dependencies:\n" ++
            "      - package: Ziggy\n" ++
            "    settings:\n" ++
            "      base:\n" ++
            "        PRODUCT_BUNDLE_IDENTIFIER: dev.ziggy.app.{s}\n" ++
            "        GENERATE_INFOPLIST_FILE: YES\n" ++
            "        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES\n" ++
            "        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES\n" ++
            "        INFOPLIST_KEY_UILaunchScreen_Generation: YES\n" ++
            "        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: UIInterfaceOrientationPortrait\n" ++
            "        CODE_SIGNING_ALLOWED: NO\n" ++
            "        CODE_SIGNING_REQUIRED: NO\n" ++
            "        CODE_SIGN_IDENTITY: \"\"\n" ++
            "        DEVELOPMENT_TEAM: \"\"\n",
        .{ app_name, normalized_sdk_path, app_name, try toIdentifierLower(arena, app_name) },
    );

    const app_swift_contents = try std.fmt.allocPrint(
        arena,
        "import SwiftUI\n" ++
            "import Ziggy\n" ++
            "\n" ++
            "@main\n" ++
            "struct {s}App: App {{\n" ++
            "    private let runtime = ZiggyRuntime(appName: \"{s}\")\n" ++
            "\n" ++
            "    var body: some Scene {{\n" ++
            "        WindowGroup {{\n" ++
            "            VStack(alignment: .leading, spacing: 12) {{\n" ++
            "                Text(\"{s}\")\n" ++
            "                    .font(.title2.bold())\n" ++
            "                Text(\"Registered plugins: \\(runtime.plugins.count)\")\n" ++
            "                Text(\"Runtime available: \\(runtime.isAvailable ? \"yes\" : \"no\")\")\n" ++
            "                Text(\"Echo: \\((try? runtime.echo(\"hello\")) ?? \"unavailable\")\")\n" ++
            "                    .font(.caption)\n" ++
            "                    .foregroundStyle(.secondary)\n" ++
            "\n" ++
            "                ForEach(runtime.plugins, id: \\.id) {{ plugin in\n" ++
            "                    Text(plugin.id)\n" ++
            "                        .font(.footnote)\n" ++
            "                }}\n" ++
            "\n" ++
            "                if let error = runtime.lastError {{\n" ++
            "                    Text(\"Runtime error: \\(error)\")\n" ++
            "                        .font(.caption2)\n" ++
            "                        .foregroundStyle(.secondary)\n" ++
            "                }}\n" ++
            "            }}\n" ++
            "            .padding(24)\n" ++
            "        }}\n" ++
            "    }}\n" ++
            "}}\n",
        .{ app_type_name, app_name, app_name },
    );

    try writeFileAtomically(io, project_yml_path, project_yml_contents);
    try writeFileAtomically(io, app_swift_path, app_swift_contents);

    runCommand(arena, io, stderr, destination_dir, &.{ "xcodegen", "generate" }, null) catch |err| {
        try stderr.print("error: failed to generate Xcode project with xcodegen: {s}\n", .{@errorName(err)});
        try stderr.writeAll("hint: install xcodegen and run `xcodegen generate` in the created directory\n");
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

pub fn createAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
) !void {
    const app_name = try sanitizeProjectName(arena, app_name_raw);
    const destination_dir = destination_dir_raw;

    std.Io.Dir.cwd().createDirPath(io, destination_dir) catch |err| {
        try stderr.print("error: failed to create destination '{s}': {s}\n", .{ destination_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const package_segment = try sanitizePackageSegment(arena, app_name);
    const package_name = try std.fmt.allocPrint(arena, "dev.ziggy.{s}", .{package_segment});

    std.Io.Dir.cwd().createDirPath(io, "/tmp/ziggy-gradle-home") catch {};
    var environ_map = try parent_environ_map.clone(arena);
    defer environ_map.deinit();
    try environ_map.put("GRADLE_USER_HOME", "/tmp/ziggy-gradle-home");

    runCommand(arena, io, stderr, destination_dir, &.{
        "gradle",
        "init",
        "--type",
        "kotlin-application",
        "--dsl",
        "kotlin",
        "--project-name",
        app_name,
        "--package",
        package_name,
        "--use-defaults",
    }, &environ_map) catch |err| {
        try stderr.print("error: failed to generate Gradle project: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    const cwd_abs = try std.process.currentPathAlloc(io, arena);
    const sdk_android_abs = try std.fs.path.resolve(arena, &.{ cwd_abs, "sdk/android" });
    const sdk_path_rel = try toForwardSlashes(arena, sdk_android_abs);

    const settings_path = try joinPath(arena, destination_dir, "settings.gradle.kts");
    const settings_contents = try std.fmt.allocPrint(
        arena,
        "plugins {{\n" ++
            "    id(\"org.gradle.toolchains.foojay-resolver-convention\") version \"1.0.0\"\n" ++
            "}}\n" ++
            "\n" ++
            "rootProject.name = \"{s}\"\n" ++
            "include(\"app\")\n" ++
            "include(\":ziggy-sdk\")\n" ++
            "project(\":ziggy-sdk\").projectDir = file(\"{s}\")\n",
        .{ app_name, sdk_path_rel },
    );
    try writeFileAtomically(io, settings_path, settings_contents);

    const app_build_path = try joinPath(arena, destination_dir, "app/build.gradle.kts");
    const app_build_contents = try std.fmt.allocPrint(
        arena,
        "plugins {{\n" ++
            "    alias(libs.plugins.kotlin.jvm)\n" ++
            "    application\n" ++
            "}}\n" ++
            "\n" ++
            "repositories {{\n" ++
            "    mavenCentral()\n" ++
            "}}\n" ++
            "\n" ++
            "dependencies {{\n" ++
            "    testImplementation(\"org.jetbrains.kotlin:kotlin-test\")\n" ++
            "    testImplementation(libs.junit.jupiter.engine)\n" ++
            "    testRuntimeOnly(\"org.junit.platform:junit-platform-launcher\")\n" ++
            "\n" ++
            "    implementation(project(\":ziggy-sdk\"))\n" ++
            "}}\n" ++
            "\n" ++
            "java {{\n" ++
            "    toolchain {{\n" ++
            "        languageVersion = JavaLanguageVersion.of(21)\n" ++
            "    }}\n" ++
            "}}\n" ++
            "\n" ++
            "application {{\n" ++
            "    mainClass = \"{s}.AppKt\"\n" ++
            "}}\n" ++
            "\n" ++
            "tasks.named<Test>(\"test\") {{\n" ++
            "    useJUnitPlatform()\n" ++
            "}}\n",
        .{package_name},
    );
    try writeFileAtomically(io, app_build_path, app_build_contents);

    const package_path = try packageNameToPath(arena, package_name);
    const app_kt_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}src{s}main{s}kotlin{s}{s}{s}App.kt",
        .{
            destination_dir,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            package_path,
            std.fs.path.sep_str,
        },
    );

    const app_kt_contents = try std.fmt.allocPrint(
        arena,
        "package {s}\n" ++
            "\n" ++
            "import dev.ziggy.ZiggyRuntime\n" ++
            "\n" ++
            "class App {{\n" ++
            "    val greeting: String\n" ++
            "        get() {{\n" ++
            "            ZiggyRuntime(appName = \"{s}\").use {{ runtime ->\n" ++
            "                val echo = runCatching {{ runtime.echo(\"hello\") }}.getOrElse {{ \"unavailable\" }}\n" ++
            "                return \"Hello Ziggy! Registered plugins: ${{runtime.plugins.size}}; runtimeAvailable=${{runtime.isAvailable}}; echo=$echo\"\n" ++
            "            }}\n" ++
            "        }}\n" ++
            "}}\n" ++
            "\n" ++
            "fun main() {{\n" ++
            "    println(App().greeting)\n" ++
            "}}\n",
        .{ package_name, app_name },
    );
    try writeFileAtomically(io, app_kt_path, app_kt_contents);

    const app_test_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}src{s}test{s}kotlin{s}{s}{s}AppTest.kt",
        .{
            destination_dir,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            package_path,
            std.fs.path.sep_str,
        },
    );
    const app_test_contents = try std.fmt.allocPrint(
        arena,
        "package {s}\n" ++
            "\n" ++
            "import kotlin.test.Test\n" ++
            "import kotlin.test.assertTrue\n" ++
            "\n" ++
            "class AppTest {{\n" ++
            "    @Test\n" ++
            "    fun appHasGreeting() {{\n" ++
            "        val greeting = App().greeting\n" ++
            "        assertTrue(greeting.contains(\"Ziggy\"))\n" ++
            "    }}\n" ++
            "}}\n",
        .{package_name},
    );
    try writeFileAtomically(io, app_test_path, app_test_contents);

    try stdout.print("created Android app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.print("next: GRADLE_USER_HOME=/tmp/gradle-home gradle -p {s} test\n", .{destination_dir});
    try stdout.flush();
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
        try out.appendSlice(allocator, "ZiggyApp");
    }

    return out.toOwnedSlice(allocator);
}
