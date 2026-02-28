//! Project scaffolding for `ziggy create`.
const std = @import("std");
const Io = std.Io;
const fs_util = @import("../../support/fs.zig");
const process_util = @import("../../support/process.zig");
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

/// Creates a full Ziggy application scaffold at `destination_dir_raw`.
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

    const dot_ziggy_dir = try joinPath(arena, destination_dir, ".ziggy");
    const lib_dir = try joinPath(arena, destination_dir, "lib");
    const plugins_dir = try joinPath(arena, destination_dir, "plugins");
    const app_sdk_dir = try joinPath(arena, dot_ziggy_dir, "sdk");
    const app_runtime_dir = try joinPath(arena, dot_ziggy_dir, "runtime");
    const app_generated_dir = try joinPath(arena, dot_ziggy_dir, "generated");
    const app_generated_swift_dir = try joinPath(arena, app_generated_dir, "swift");
    const app_generated_kotlin_dir = try joinPath(arena, app_generated_dir, "kotlin");
    const app_generated_zig_dir = try joinPath(arena, app_generated_dir, "zig");
    const app_plugins_meta_dir = try joinPath(arena, dot_ziggy_dir, "plugins");

    for (&[_][]const u8{
        lib_dir,
        plugins_dir,
        app_sdk_dir,
        app_runtime_dir,
        app_generated_dir,
        app_generated_swift_dir,
        app_generated_kotlin_dir,
        app_generated_zig_dir,
        app_plugins_meta_dir,
    }) |dir_path| {
        std.Io.Dir.cwd().createDirPath(io, dir_path) catch |err| {
            try stderr.print("error: failed to create '{s}': {s}\n", .{ dir_path, @errorName(err) });
            try stderr.flush();
            return error.CreateFailed;
        };
    }

    fs_util.removeTreeIfExists(io, app_sdk_dir) catch {};
    fs_util.removeTreeIfExists(io, app_runtime_dir) catch {};

    fs_util.copyTree(arena, io, resolved.sdk_dir, app_sdk_dir) catch |err| {
        try stderr.print("error: failed to copy SDK into app (.ziggy/sdk): {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };
    fs_util.copyTree(arena, io, resolved.runtime_dir, app_runtime_dir) catch |err| {
        try stderr.print("error: failed to copy runtime into app (.ziggy/runtime): {s}\n", .{@errorName(err)});
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
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/ziggy.yaml", try joinPath(arena, destination_dir, "ziggy.yaml"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/ziggy.api.zig", try joinPath(arena, destination_dir, "ziggy.api.zig"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/lib/main.zig", try joinPath(arena, lib_dir, "main.zig"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/plugins/README.md", try joinPath(arena, plugins_dir, "README.md"), &template_tokens);

    const api_path = try joinPath(arena, destination_dir, "ziggy.api.zig");
    codegen_cmd.generateProject(arena, io, stderr, stdout, destination_dir, api_path) catch |err| {
        try stderr.print("error: failed to run initial codegen: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    if (platforms.ios) {
        const ios_dir = try joinPath(arena, destination_dir, "ios");
        createIos(arena, io, stderr, stdout, resolved.templates_dir, app_name, ios_dir) catch return error.CreateFailed;
    }
    if (platforms.android) {
        const android_dir = try joinPath(arena, destination_dir, "android");
        createAndroid(arena, io, parent_environ_map, stderr, stdout, app_name, android_dir) catch return error.CreateFailed;
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
            "# macOS (placeholder)\n\nDesktop scaffolding will be added in a future Ziggy release.\n",
        );
    }

    try stdout.print("created Ziggy app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.flush();
}

/// Creates the iOS host scaffold and optionally runs `xcodegen generate`.
pub fn createIos(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    templates_root: []const u8,
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

    const sources_dir = try joinPath(arena, destination_dir, "Sources");
    std.Io.Dir.cwd().createDirPath(io, sources_dir) catch |err| {
        try stderr.print("error: failed to create sources dir '{s}': {s}\n", .{ sources_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const tokens = [_]fs_util.RenderToken{
        .{ .key = "APP_NAME", .value = app_name },
        .{ .key = "APP_IDENTIFIER", .value = try toIdentifierLower(arena, app_name) },
        .{ .key = "APP_TYPE_NAME", .value = try toSwiftTypeName(arena, app_name) },
    };

    const project_yml_path = try joinPath(arena, destination_dir, "project.yml");
    const app_swift_path = try joinPath(arena, sources_dir, "App.swift");

    try renderTemplateToPath(arena, io, templates_root, "app/ios/project.yml", project_yml_path, &tokens);
    try renderTemplateToPath(arena, io, templates_root, "app/ios/Sources/App.swift", app_swift_path, &tokens);

    if (process_util.commandExists(arena, io, "xcodegen")) {
        _ = process_util.runChecked(arena, io, stderr, destination_dir, &.{ "xcodegen", "generate" }, null, "generate iOS project") catch |err| {
            try stderr.print("warning: xcodegen failed: {s}\n", .{@errorName(err)});
            try stderr.flush();
        };
    } else {
        try stderr.writeAll("warning: xcodegen not found; run `xcodegen generate` inside ios/ when installed\n");
        try stderr.flush();
    }

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
        "9.3.1",
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
        "    alias(libs.plugins.kotlin.compose) apply false\n" ++
        "}\n";
    try writeFileAtomically(io, root_build_path, root_build_contents);

    const gradle_properties_path = try joinPath(arena, destination_dir, "gradle.properties");
    const gradle_properties_contents =
        "org.gradle.jvmargs=-Xmx4096m -Dfile.encoding=UTF-8\n" ++
        "org.gradle.parallel=true\n" ++
        "android.useAndroidX=true\n" ++
        "kotlin.code.style=official\n" ++
        "org.gradle.configuration-cache=true\n";
    try writeFileAtomically(io, gradle_properties_path, gradle_properties_contents);

    const version_catalog_path = try joinPath(arena, destination_dir, "gradle/libs.versions.toml");
    const version_catalog_contents =
        "[versions]\n" ++
        "agp = \"9.0.0\"\n" ++
        "kotlin = \"2.2.21\"\n" ++
        "androidx-core-ktx = \"1.15.0\"\n" ++
        "androidx-lifecycle-runtime-ktx = \"2.8.7\"\n" ++
        "androidx-activity-compose = \"1.9.3\"\n" ++
        "androidx-compose-bom = \"2024.10.01\"\n" ++
        "junit = \"4.13.2\"\n" ++
        "androidx-junit = \"1.2.1\"\n" ++
        "espresso-core = \"3.6.1\"\n" ++
        "\n" ++
        "[libraries]\n" ++
        "androidx-core-ktx = { module = \"androidx.core:core-ktx\", version.ref = \"androidx-core-ktx\" }\n" ++
        "androidx-lifecycle-runtime-ktx = { module = \"androidx.lifecycle:lifecycle-runtime-ktx\", version.ref = \"androidx-lifecycle-runtime-ktx\" }\n" ++
        "androidx-activity-compose = { module = \"androidx.activity:activity-compose\", version.ref = \"androidx-activity-compose\" }\n" ++
        "androidx-compose-bom = { module = \"androidx.compose:compose-bom\", version.ref = \"androidx-compose-bom\" }\n" ++
        "androidx-ui = { module = \"androidx.compose.ui:ui\" }\n" ++
        "androidx-ui-graphics = { module = \"androidx.compose.ui:ui-graphics\" }\n" ++
        "androidx-ui-tooling = { module = \"androidx.compose.ui:ui-tooling\" }\n" ++
        "androidx-ui-tooling-preview = { module = \"androidx.compose.ui:ui-tooling-preview\" }\n" ++
        "androidx-ui-test-manifest = { module = \"androidx.compose.ui:ui-test-manifest\" }\n" ++
        "androidx-ui-test-junit4 = { module = \"androidx.compose.ui:ui-test-junit4\" }\n" ++
        "androidx-material3 = { module = \"androidx.compose.material3:material3\" }\n" ++
        "junit = { module = \"junit:junit\", version.ref = \"junit\" }\n" ++
        "androidx-junit = { module = \"androidx.test.ext:junit\", version.ref = \"androidx-junit\" }\n" ++
        "espresso-core = { module = \"androidx.test.espresso:espresso-core\", version.ref = \"espresso-core\" }\n" ++
        "\n" ++
        "[plugins]\n" ++
        "android-application = { id = \"com.android.application\", version.ref = \"agp\" }\n" ++
        "kotlin-compose = { id = \"org.jetbrains.kotlin.plugin.compose\", version.ref = \"kotlin\" }\n";
    try writeFileAtomically(io, version_catalog_path, version_catalog_contents);

    const app_build_path = try joinPath(arena, destination_dir, "app/build.gradle.kts");
    const app_build_contents = try std.fmt.allocPrint(
        arena,
        "plugins {{\n" ++
            "    alias(libs.plugins.android.application)\n" ++
            "    alias(libs.plugins.kotlin.compose)\n" ++
            "}}\n" ++
            "\n" ++
            "android {{\n" ++
            "    namespace = \"{s}\"\n" ++
            "    compileSdk = 36\n" ++
            "\n" ++
            "    defaultConfig {{\n" ++
            "        applicationId = \"{s}\"\n" ++
            "        minSdk = 24\n" ++
            "        targetSdk = 36\n" ++
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
            "        sourceCompatibility = JavaVersion.VERSION_21\n" ++
            "        targetCompatibility = JavaVersion.VERSION_21\n" ++
            "    }}\n" ++
            "\n" ++
            "    buildFeatures {{\n" ++
            "        compose = true\n" ++
            "    }}\n" ++
            "\n" ++
            "    packaging {{\n" ++
            "        resources {{\n" ++
            "            excludes += \"/META-INF/{{AL2.0,LGPL2.1}}\"\n" ++
            "        }}\n" ++
            "    }}\n" ++
            "\n" ++
            "    sourceSets {{\n" ++
            "        getByName(\"main\") {{\n" ++
            "            kotlin.directories.add(rootProject.file(\"../.ziggy/generated/kotlin\").path)\n" ++
            "        }}\n" ++
            "    }}\n" ++
            "}}\n" ++
            "\n" ++
            "dependencies {{\n" ++
            "    implementation(libs.androidx.core.ktx)\n" ++
            "    implementation(libs.androidx.lifecycle.runtime.ktx)\n" ++
            "    implementation(libs.androidx.activity.compose)\n" ++
            "    implementation(platform(libs.androidx.compose.bom))\n" ++
            "    implementation(libs.androidx.ui)\n" ++
            "    implementation(libs.androidx.ui.graphics)\n" ++
            "    implementation(libs.androidx.ui.tooling.preview)\n" ++
            "    implementation(libs.androidx.material3)\n" ++
            "\n" ++
            "    testImplementation(libs.junit)\n" ++
            "    androidTestImplementation(libs.androidx.junit)\n" ++
            "    androidTestImplementation(libs.espresso.core)\n" ++
            "    androidTestImplementation(platform(libs.androidx.compose.bom))\n" ++
            "    androidTestImplementation(libs.androidx.ui.test.junit4)\n" ++
            "\n" ++
            "    debugImplementation(libs.androidx.ui.tooling)\n" ++
            "    debugImplementation(libs.androidx.ui.test.manifest)\n" ++
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
            "        android:theme=\"@style/Theme.{s}\">\n" ++
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
        .{app_type_name},
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
            "import android.util.Log\n" ++
            "import androidx.activity.ComponentActivity\n" ++
            "import androidx.activity.compose.setContent\n" ++
            "import androidx.activity.enableEdgeToEdge\n" ++
            "import androidx.compose.foundation.layout.Arrangement\n" ++
            "import androidx.compose.foundation.layout.Column\n" ++
            "import androidx.compose.foundation.layout.fillMaxSize\n" ++
            "import androidx.compose.foundation.layout.padding\n" ++
            "import androidx.compose.material3.Button\n" ++
            "import androidx.compose.material3.MaterialTheme\n" ++
            "import androidx.compose.material3.Scaffold\n" ++
            "import androidx.compose.material3.Text\n" ++
            "import androidx.compose.runtime.Composable\n" ++
            "import androidx.compose.runtime.getValue\n" ++
            "import androidx.compose.runtime.mutableStateOf\n" ++
            "import androidx.compose.runtime.remember\n" ++
            "import androidx.compose.runtime.setValue\n" ++
            "import androidx.compose.ui.Modifier\n" ++
            "import androidx.compose.ui.tooling.preview.Preview\n" ++
            "import androidx.compose.ui.unit.dp\n" ++
            "import dev.ziggy.generated.ZiggyGeneratedApi\n" ++
            "import {s}.ui.theme.{s}Theme\n" ++
            "\n" ++
            "class MainActivity : ComponentActivity() {{\n" ++
            "    override fun onCreate(savedInstanceState: Bundle?) {{\n" ++
            "        super.onCreate(savedInstanceState)\n" ++
            "        enableEdgeToEdge()\n" ++
            "        setContent {{\n" ++
            "            {s}Theme {{\n" ++
            "                Scaffold(modifier = Modifier.fillMaxSize()) {{ innerPadding ->\n" ++
            "                    Greeting(\n" ++
            "                        appName = \"{s}\",\n" ++
            "                        modifier = Modifier.padding(innerPadding),\n" ++
            "                    )\n" ++
            "                }}\n" ++
            "            }}\n" ++
            "        }}\n" ++
            "    }}\n" ++
            "}}\n" ++
            "\n" ++
            "@Composable\n" ++
            "private fun Greeting(appName: String, modifier: Modifier = Modifier) {{\n" ++
            "    val api = remember {{ ZiggyGeneratedApi() }}\n" ++
            "    var clickCount by remember {{ mutableStateOf(0) }}\n" ++
            "    val echoed = remember {{ api.echo(\"hello\") }}\n" ++
            "    Column(\n" ++
            "        modifier = modifier\n" ++
            "            .fillMaxSize()\n" ++
            "            .padding(24.dp),\n" ++
            "        verticalArrangement = Arrangement.spacedBy(12.dp),\n" ++
            "    ) {{\n" ++
            "        Text(\n" ++
            "            text = \"Hello from $appName\",\n" ++
            "            style = MaterialTheme.typography.headlineSmall,\n" ++
            "        )\n" ++
            "        Text(\n" ++
            "            text = \"Button clicks: $clickCount\",\n" ++
            "            style = MaterialTheme.typography.bodyMedium,\n" ++
            "        )\n" ++
            "        Text(\n" ++
            "            text = \"Generated API echo: $echoed\",\n" ++
            "            style = MaterialTheme.typography.bodySmall,\n" ++
            "        )\n" ++
            "        Button(\n" ++
            "            onClick = {{\n" ++
            "                clickCount += 1\n" ++
            "                Log.i(\"{s}\", \"Compose button clicked: $clickCount\")\n" ++
            "                println(\"Compose button clicked: $clickCount\")\n" ++
            "            }},\n" ++
            "        ) {{\n" ++
            "            Text(\"Click me\")\n" ++
            "        }}\n" ++
            "    }}\n" ++
            "}}\n" ++
            "\n" ++
            "@Preview(showBackground = true)\n" ++
            "@Composable\n" ++
            "private fun GreetingPreview() {{\n" ++
            "    {s}Theme {{\n" ++
            "        Greeting(appName = \"{s}\")\n" ++
            "    }}\n" ++
            "}}\n",
        .{
            package_name,
            package_name,
            app_type_name,
            app_type_name,
            app_name,
            app_name,
            app_type_name,
            app_name,
        },
    );
    try writeFileAtomically(io, main_activity_path, main_activity_contents);

    const theme_dir = try std.fmt.allocPrint(
        arena,
        "{s}{s}app{s}src{s}main{s}java{s}{s}{s}ui{s}theme",
        .{
            destination_dir,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            package_path,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
        },
    );

    const color_path = try std.fmt.allocPrint(arena, "{s}{s}Color.kt", .{ theme_dir, std.fs.path.sep_str });
    const color_contents = try std.fmt.allocPrint(
        arena,
        "package {s}.ui.theme\n" ++
            "\n" ++
            "import androidx.compose.ui.graphics.Color\n" ++
            "\n" ++
            "val Purple80 = Color(0xFFD0BCFF)\n" ++
            "val PurpleGrey80 = Color(0xFFCCC2DC)\n" ++
            "val Pink80 = Color(0xFFEFB8C8)\n" ++
            "\n" ++
            "val Purple40 = Color(0xFF6650A4)\n" ++
            "val PurpleGrey40 = Color(0xFF625B71)\n" ++
            "val Pink40 = Color(0xFF7D5260)\n",
        .{package_name},
    );
    try writeFileAtomically(io, color_path, color_contents);

    const type_path = try std.fmt.allocPrint(arena, "{s}{s}Type.kt", .{ theme_dir, std.fs.path.sep_str });
    const type_contents = try std.fmt.allocPrint(
        arena,
        "package {s}.ui.theme\n" ++
            "\n" ++
            "import androidx.compose.material3.Typography\n" ++
            "\n" ++
            "val Typography = Typography()\n",
        .{package_name},
    );
    try writeFileAtomically(io, type_path, type_contents);

    const theme_path = try std.fmt.allocPrint(arena, "{s}{s}Theme.kt", .{ theme_dir, std.fs.path.sep_str });
    const theme_contents = try std.fmt.allocPrint(
        arena,
        "package {s}.ui.theme\n" ++
            "\n" ++
            "import android.os.Build\n" ++
            "import androidx.compose.foundation.isSystemInDarkTheme\n" ++
            "import androidx.compose.material3.MaterialTheme\n" ++
            "import androidx.compose.material3.darkColorScheme\n" ++
            "import androidx.compose.material3.dynamicDarkColorScheme\n" ++
            "import androidx.compose.material3.dynamicLightColorScheme\n" ++
            "import androidx.compose.material3.lightColorScheme\n" ++
            "import androidx.compose.runtime.Composable\n" ++
            "import androidx.compose.ui.platform.LocalContext\n" ++
            "\n" ++
            "private val DarkColorScheme = darkColorScheme(\n" ++
            "    primary = Purple80,\n" ++
            "    secondary = PurpleGrey80,\n" ++
            "    tertiary = Pink80,\n" ++
            ")\n" ++
            "\n" ++
            "private val LightColorScheme = lightColorScheme(\n" ++
            "    primary = Purple40,\n" ++
            "    secondary = PurpleGrey40,\n" ++
            "    tertiary = Pink40,\n" ++
            ")\n" ++
            "\n" ++
            "@Composable\n" ++
            "fun {s}Theme(\n" ++
            "    darkTheme: Boolean = isSystemInDarkTheme(),\n" ++
            "    dynamicColor: Boolean = true,\n" ++
            "    content: @Composable () -> Unit,\n" ++
            ") {{\n" ++
            "    val colorScheme = when {{\n" ++
            "        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {{\n" ++
            "            val context = LocalContext.current\n" ++
            "            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)\n" ++
            "        }}\n" ++
            "\n" ++
            "        darkTheme -> DarkColorScheme\n" ++
            "        else -> LightColorScheme\n" ++
            "    }}\n" ++
            "\n" ++
            "    MaterialTheme(\n" ++
            "        colorScheme = colorScheme,\n" ++
            "        typography = Typography,\n" ++
            "        content = content,\n" ++
            "    )\n" ++
            "}}\n",
        .{ package_name, app_type_name },
    );
    try writeFileAtomically(io, theme_path, theme_contents);

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
    const themes_contents = try std.fmt.allocPrint(
        arena,
        "<resources xmlns:tools=\"http://schemas.android.com/tools\">\n" ++
            "    <style name=\"Theme.{s}\" parent=\"android:Theme.Material.Light.NoActionBar\">\n" ++
            "        <item name=\"android:statusBarColor\">@android:color/transparent</item>\n" ++
            "    </style>\n" ++
            "</resources>\n",
        .{app_type_name},
    );
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
