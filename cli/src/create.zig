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
    const package_path = try packageNameToPath(arena, package_name);

    std.Io.Dir.cwd().createDirPath(io, "/tmp/ziggy-gradle-home") catch {};
    var environ_map = try parent_environ_map.clone(arena);
    defer environ_map.deinit();
    try environ_map.put("GRADLE_USER_HOME", "/tmp/ziggy-gradle-home");

    runCommand(arena, io, stderr, destination_dir, &.{
        "gradle",
        "init",
        "--type",
        "basic",
        "--dsl",
        "kotlin",
        "--project-name",
        app_name,
        "--use-defaults",
        "--overwrite",
    }, &environ_map) catch |err| {
        try stderr.print("error: failed to initialize Gradle project: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    runCommand(arena, io, stderr, destination_dir, &.{
        "gradle",
        "wrapper",
        "--gradle-version",
        "8.7",
        "--distribution-type",
        "all",
    }, &environ_map) catch |err| {
        try stderr.print("error: failed to configure Gradle wrapper: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    const settings_path = try joinPath(arena, destination_dir, "settings.gradle.kts");
    const settings_contents = try std.fmt.allocPrint(
        arena,
        "pluginManagement {{\n" ++
            "    repositories {{\n" ++
            "        google()\n" ++
            "        mavenCentral()\n" ++
            "        gradlePluginPortal()\n" ++
            "    }}\n" ++
            "}}\n" ++
            "\n" ++
            "dependencyResolutionManagement {{\n" ++
            "    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)\n" ++
            "    repositories {{\n" ++
            "        google()\n" ++
            "        mavenCentral()\n" ++
            "    }}\n" ++
            "}}\n" ++
            "\n" ++
            "rootProject.name = \"{s}\"\n" ++
            "include(\":app\")\n",
        .{app_name},
    );
    try writeFileAtomically(io, settings_path, settings_contents);

    const root_build_path = try joinPath(arena, destination_dir, "build.gradle.kts");
    const root_build_contents =
        "plugins {\n" ++
        "    alias(libs.plugins.android.application) apply false\n" ++
        "    alias(libs.plugins.kotlin.android) apply false\n" ++
        "}\n";
    try writeFileAtomically(io, root_build_path, root_build_contents);

    const gradle_properties_path = try joinPath(arena, destination_dir, "gradle.properties");
    const gradle_properties_contents =
        "org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8\n" ++
        "android.useAndroidX=true\n" ++
        "kotlin.code.style=official\n" ++
        "org.gradle.configuration-cache=true\n";
    try writeFileAtomically(io, gradle_properties_path, gradle_properties_contents);

    const version_catalog_path = try joinPath(arena, destination_dir, "gradle/libs.versions.toml");
    const version_catalog_contents =
        "[versions]\n" ++
        "agp = \"8.5.2\"\n" ++
        "kotlin = \"1.9.24\"\n" ++
        "\n" ++
        "[plugins]\n" ++
        "android-application = { id = \"com.android.application\", version.ref = \"agp\" }\n" ++
        "kotlin-android = { id = \"org.jetbrains.kotlin.android\", version.ref = \"kotlin\" }\n";
    try writeFileAtomically(io, version_catalog_path, version_catalog_contents);

    const app_build_path = try joinPath(arena, destination_dir, "app/build.gradle.kts");
    const app_build_contents = try std.fmt.allocPrint(
        arena,
        "plugins {{\n" ++
            "    alias(libs.plugins.android.application)\n" ++
            "    alias(libs.plugins.kotlin.android)\n" ++
            "}}\n" ++
            "\n" ++
            "android {{\n" ++
            "    namespace = \"{s}\"\n" ++
            "    compileSdk = 35\n" ++
            "\n" ++
            "    defaultConfig {{\n" ++
            "        applicationId = \"{s}\"\n" ++
            "        minSdk = 24\n" ++
            "        targetSdk = 35\n" ++
            "        versionCode = 1\n" ++
            "        versionName = \"1.0\"\n" ++
            "        testInstrumentationRunner = \"androidx.test.runner.AndroidJUnitRunner\"\n" ++
            "    }}\n" ++
            "\n" ++
            "    buildTypes {{\n" ++
            "        release {{\n" ++
            "            isMinifyEnabled = false\n" ++
            "            proguardFiles(\n" ++
            "                getDefaultProguardFile(\"proguard-android-optimize.txt\"),\n" ++
            "                \"proguard-rules.pro\"\n" ++
            "            )\n" ++
            "        }}\n" ++
            "    }}\n" ++
            "\n" ++
            "    compileOptions {{\n" ++
            "        sourceCompatibility = JavaVersion.VERSION_17\n" ++
            "        targetCompatibility = JavaVersion.VERSION_17\n" ++
            "    }}\n" ++
            "    kotlinOptions {{\n" ++
            "        jvmTarget = \"17\"\n" ++
            "    }}\n" ++
            "}}\n" ++
            "\n" ++
            "dependencies {{\n" ++
            "    implementation(\"androidx.core:core-ktx:1.13.1\")\n" ++
            "    implementation(\"androidx.appcompat:appcompat:1.7.0\")\n" ++
            "    implementation(\"com.google.android.material:material:1.12.0\")\n" ++
            "    implementation(\"androidx.activity:activity-ktx:1.9.0\")\n" ++
            "\n" ++
            "    testImplementation(\"junit:junit:4.13.2\")\n" ++
            "    androidTestImplementation(\"androidx.test.ext:junit:1.2.1\")\n" ++
            "    androidTestImplementation(\"androidx.test.espresso:espresso-core:3.6.1\")\n" ++
            "}}\n",
        .{ package_name, package_name },
    );
    try writeFileAtomically(io, app_build_path, app_build_contents);

    const manifest_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}src{s}main{s}AndroidManifest.xml",
        .{
            destination_dir,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
        },
    );
    const manifest_contents = try std.fmt.allocPrint(
        arena,
        "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n" ++
            "\n" ++
            "    <application\n" ++
            "        android:allowBackup=\"true\"\n" ++
            "        android:label=\"@string/app_name\"\n" ++
            "        android:supportsRtl=\"true\"\n" ++
            "        android:theme=\"@style/Theme.Ziggy\">\n" ++
            "        <activity\n" ++
            "            android:name=\".MainActivity\"\n" ++
            "            android:exported=\"true\">\n" ++
            "            <intent-filter>\n" ++
            "                <action android:name=\"android.intent.action.MAIN\" />\n" ++
            "                <category android:name=\"android.intent.category.LAUNCHER\" />\n" ++
            "            </intent-filter>\n" ++
            "        </activity>\n" ++
            "    </application>\n" ++
            "\n" ++
            "</manifest>\n",
        .{},
    );
    try writeFileAtomically(io, manifest_path, manifest_contents);

    const main_activity_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}src{s}main{s}java{s}{s}{s}MainActivity.kt",
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
    const main_activity_contents = try std.fmt.allocPrint(
        arena,
        "package {s}\n" ++
            "\n" ++
            "import android.os.Bundle\n" ++
            "import android.widget.TextView\n" ++
            "import androidx.appcompat.app.AppCompatActivity\n" ++
            "\n" ++
            "class MainActivity : AppCompatActivity() {{\n" ++
            "    override fun onCreate(savedInstanceState: Bundle?) {{\n" ++
            "        super.onCreate(savedInstanceState)\n" ++
            "        val label = TextView(this)\n" ++
            "        label.text = \"Hello from {s}\"\n" ++
            "        val padding = (24 * resources.displayMetrics.density).toInt()\n" ++
            "        label.setPadding(padding, padding, padding, padding)\n" ++
            "        setContentView(label)\n" ++
            "    }}\n" ++
            "}}\n",
        .{ package_name, app_name },
    );
    try writeFileAtomically(io, main_activity_path, main_activity_contents);

    const app_test_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}src{s}test{s}java{s}{s}{s}MainActivitySmokeTest.kt",
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
            "import org.junit.Test\n" ++
            "import org.junit.Assert.assertTrue\n" ++
            "\n" ++
            "class MainActivitySmokeTest {{\n" ++
            "    @Test\n" ++
            "    fun packageNameLooksValid() {{\n" ++
            "        assertTrue(\"{s}\".contains(\".\"))\n" ++
            "    }}\n" ++
            "}}\n",
        .{ package_name, package_name },
    );
    try writeFileAtomically(io, app_test_path, app_test_contents);

    const strings_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}src{s}main{s}res{s}values{s}strings.xml",
        .{
            destination_dir,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
        },
    );
    const strings_contents = try std.fmt.allocPrint(
        arena,
        "<resources>\n" ++
            "    <string name=\"app_name\">{s}</string>\n" ++
            "</resources>\n",
        .{app_name},
    );
    try writeFileAtomically(io, strings_path, strings_contents);

    const themes_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}src{s}main{s}res{s}values{s}themes.xml",
        .{
            destination_dir,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
        },
    );
    const themes_contents =
        "<resources xmlns:tools=\"http://schemas.android.com/tools\">\n" ++
        "    <style name=\"Theme.Ziggy\" parent=\"Theme.Material3.DayNight.NoActionBar\">\n" ++
        "        <item name=\"android:statusBarColor\">@android:color/transparent</item>\n" ++
        "    </style>\n" ++
        "</resources>\n";
    try writeFileAtomically(io, themes_path, themes_contents);

    const proguard_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}proguard-rules.pro",
        .{
            destination_dir,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
        },
    );
    try writeFileAtomically(io, proguard_path, "# Ziggy Android app ProGuard rules.\n");

    const sdk_dir = parent_environ_map.get("ANDROID_SDK_ROOT") orelse parent_environ_map.get("ANDROID_HOME");
    if (sdk_dir) |sdk| {
        const local_properties_path = try joinPath(arena, destination_dir, "local.properties");
        const escaped_sdk = try escapeLocalPropertiesValue(arena, sdk);
        const local_properties_contents = try std.fmt.allocPrint(arena, "sdk.dir={s}\n", .{escaped_sdk});
        try writeFileAtomically(io, local_properties_path, local_properties_contents);
    }

    try stdout.print("created Android app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.print("next: (cd {s} && ./gradlew :app:assembleDebug)\n", .{destination_dir});
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
        try out.appendSlice(allocator, "ZiggyApp");
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
    const got = try packageNameToPath(std.testing.allocator, "dev.ziggy.demo");
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
    const got = try escapeLocalPropertiesValue(std.testing.allocator, "C:\\Users\\ziggy\\sdk");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("C:\\\\Users\\\\ziggy\\\\sdk", got);
}
