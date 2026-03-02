//! Android Gradle file compatibility migrations for host-managed FFI.
//!
//! ## Background
//! Recent Android Gradle plugin updates changed the expected type of
//! `sourceSets.main.jniLibs.directories` entries from `File` to `String` path
//! values in Kotlin DSL usage. Older generated Wizig hosts still write a
//! `File`, which fails script compilation during `wizig run`. IDE-launched
//! Gradle builds also often run without a shell `PATH`, so direct `"zig"`
//! command invocation can fail even when Zig is installed.
//!
//! ## Scope
//! This module performs a targeted, idempotent migration over
//! `<project>/<module>/build.gradle.kts` before Gradle execution:
//! - `jniLibs.directories.add(rootProject.file(...))`
//! - `jniLibs.directories.add(rootProject.file(...).path)`
//! - `commandLine("zig", ...)` -> `commandLine(discoverWizigZigBinary(), ...)`
//! - `-OReleaseFast` -> configurable `-O${requestedWizigOptimize}`
//!
//! ## Safety
//! The migration only rewrites a known Wizig-managed statement and leaves all
//! other user Gradle content unchanged.
const std = @import("std");

const fs_utils = @import("fs_utils.zig");

/// Result metadata describing whether Android Gradle migration touched the file.
pub const MigrationSummary = struct {
    /// True when `<module>/build.gradle.kts` existed and was inspected.
    inspected: bool = false,
    /// True when compatibility rewrites were applied and persisted.
    patched: bool = false,
};

const old_jni_libs_line =
    "jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\"))";
const new_jni_libs_line =
    "jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\").path)";
const old_zig_command_line = "            \"zig\",\n";
const new_zig_command_line = "            discoverWizigZigBinary(),\n";
const old_zig_command_inline = "commandLine(\"zig\",";
const new_zig_command_inline = "commandLine(discoverWizigZigBinary(),";
const old_optimize_line = "            \"-OReleaseFast\",\n";
const new_optimize_line = "            \"-O${requestedWizigOptimize}\",\n";
const old_optimize_inline = "\"-OReleaseFast\",";
const new_optimize_inline = "\"-O${requestedWizigOptimize}\",";
const malformed_optimize_error_line =
    "        \"Unsupported Wizig FFI optimize mode '${requestedWizigOptimize}'. Supported values: ${supportedWizigOptimizeModes.joinToString(\\\", \\\")}\"\n";
const fixed_optimize_error_line =
    "        \"Unsupported Wizig FFI optimize mode '${requestedWizigOptimize}'. Supported values: ${supportedWizigOptimizeModes.joinToString(\", \")}\"\n";
const java_file_check_line = "        if (java.io.File(candidate).canExecute()) return candidate\n";
const root_file_check_line = "        if (rootProject.file(candidate).canExecute()) return candidate\n";
const old_local_properties_block =
    "    val localProperties = java.util.Properties()\n" ++
    "    val localPropertiesFile = rootProject.file(\"local.properties\")\n" ++
    "    if (localPropertiesFile.isFile) {\n" ++
    "        runCatching {\n" ++
    "            localPropertiesFile.inputStream().use { stream -> localProperties.load(stream) }\n" ++
    "            val fromLocalProperties = localProperties.getProperty(\"wizig.zig.bin\")?.trim()\n" ++
    "            if (!fromLocalProperties.isNullOrBlank()) return fromLocalProperties\n" ++
    "        }\n" ++
    "    }\n\n";
const new_local_properties_block =
    "    val localPropertiesFile = rootProject.file(\"local.properties\")\n" ++
    "    if (localPropertiesFile.isFile) {\n" ++
    "        val fromLocalProperties = runCatching {\n" ++
    "            localPropertiesFile.readLines()\n" ++
    "                .asSequence()\n" ++
    "                .map { line -> line.trim() }\n" ++
    "                .firstOrNull { line -> line.startsWith(\"wizig.zig.bin=\") }\n" ++
    "                ?.substringAfter(\"=\")\n" ++
    "                ?.trim()\n" ++
    "        }.getOrNull()\n" ++
    "        if (!fromLocalProperties.isNullOrBlank()) return fromLocalProperties\n" ++
    "    }\n\n";

const abi_suffix_marker = "fun abiTaskSuffix(abi: String): String =";
const optimize_marker = "val requestedWizigOptimize: String =";
const zig_discovery_marker = "fun discoverWizigZigBinary(): String {";
const local_properties_probe_marker = "    val localPropertiesFile = rootProject.file(\"local.properties\")\n";
const path_probe_marker = "    val pathProbe = runCatching {\n";

const optimize_block =
    "val supportedWizigOptimizeModes: Set<String> = setOf(\"Debug\", \"ReleaseFast\", \"ReleaseSafe\", \"ReleaseSmall\")\n\n" ++
    "val requestedWizigOptimize: String = providers.gradleProperty(\"wizig.ffi.optimize\").orNull ?: \"Debug\"\n" ++
    "if (requestedWizigOptimize !in supportedWizigOptimizeModes) {\n" ++
    "    throw org.gradle.api.GradleException(\n" ++
    "        \"Unsupported Wizig FFI optimize mode '${requestedWizigOptimize}'. Supported values: ${supportedWizigOptimizeModes.joinToString(\", \")}\"\n" ++
    "    )\n" ++
    "}\n\n";

const zig_discovery_block =
    "fun discoverWizigZigBinary(): String {\n" ++
    "    val explicit = providers.gradleProperty(\"wizig.zig.bin\").orNull ?: System.getenv(\"ZIG_BINARY\")\n" ++
    "    if (!explicit.isNullOrBlank()) return explicit\n\n" ++
    "    val localPropertiesFile = rootProject.file(\"local.properties\")\n" ++
    "    if (localPropertiesFile.isFile) {\n" ++
    "        val fromLocalProperties = runCatching {\n" ++
    "            localPropertiesFile.readLines()\n" ++
    "                .asSequence()\n" ++
    "                .map { line -> line.trim() }\n" ++
    "                .firstOrNull { line -> line.startsWith(\"wizig.zig.bin=\") }\n" ++
    "                ?.substringAfter(\"=\")\n" ++
    "                ?.trim()\n" ++
    "        }.getOrNull()\n" ++
    "        if (!fromLocalProperties.isNullOrBlank()) return fromLocalProperties\n" ++
    "    }\n\n" ++
    "    val pathProbe = runCatching {\n" ++
    "        val process = ProcessBuilder(\"which\", \"zig\").redirectErrorStream(true).start()\n" ++
    "        val output = process.inputStream.bufferedReader().readText().trim()\n" ++
    "        if (process.waitFor() == 0 && output.isNotEmpty()) output else null\n" ++
    "    }.getOrNull()\n" ++
    "    if (!pathProbe.isNullOrBlank()) return pathProbe\n\n" ++
    "    val home = System.getProperty(\"user.home\") ?: \"\"\n" ++
    "    val candidates = listOf(\n" ++
    "        \"$home/.zvm/master/zig\",\n" ++
    "        \"$home/.zvm/bin/zig\",\n" ++
    "        \"$home/.local/bin/zig\",\n" ++
    "        \"/opt/homebrew/bin/zig\",\n" ++
    "        \"/usr/local/bin/zig\",\n" ++
    "    )\n" ++
    "    for (candidate in candidates) {\n" ++
    "        if (rootProject.file(candidate).canExecute()) return candidate\n" ++
    "    }\n\n" ++
    "    throw org.gradle.api.GradleException(\n" ++
    "        \"zig is not installed or discoverable (PATH/wizig.zig.bin/ZIG_BINARY/common locations)\"\n" ++
    "    )\n" ++
    "}\n\n";

/// Ensures Android host build file compatibility for current Gradle APIs.
///
/// This function is intentionally cheap (`read -> patch -> compare -> write`),
/// so it can be called on every Android run invocation without measurable
/// overhead.
pub fn ensureBuildGradleKtsCompatibility(
    arena: std.mem.Allocator,
    io: std.Io,
    project_dir: []const u8,
    module: []const u8,
) !MigrationSummary {
    const module_dir = try fs_utils.joinPath(arena, project_dir, module);
    const build_gradle_kts = try fs_utils.joinPath(arena, module_dir, "build.gradle.kts");
    if (!fs_utils.pathExists(io, build_gradle_kts)) return .{};

    const original = try std.Io.Dir.cwd().readFileAlloc(io, build_gradle_kts, arena, .limited(4 * 1024 * 1024));
    const patched = try patchBuildGradleKtsText(arena, original);
    if (std.mem.eql(u8, original, patched)) {
        return .{ .inspected = true, .patched = false };
    }

    try fs_utils.writeFileAtomically(io, build_gradle_kts, patched);
    return .{ .inspected = true, .patched = true };
}

/// Applies in-memory text migrations for `app/build.gradle.kts`.
fn patchBuildGradleKtsText(
    arena: std.mem.Allocator,
    original: []const u8,
) ![]const u8 {
    var patched = original;
    patched = try replaceAll(arena, patched, old_jni_libs_line, new_jni_libs_line);
    patched = try replaceAll(arena, patched, old_zig_command_line, new_zig_command_line);
    patched = try replaceAll(arena, patched, old_zig_command_inline, new_zig_command_inline);
    patched = try replaceAll(arena, patched, old_optimize_line, new_optimize_line);
    patched = try replaceAll(arena, patched, old_optimize_inline, new_optimize_inline);
    patched = try replaceAll(arena, patched, malformed_optimize_error_line, fixed_optimize_error_line);
    patched = try replaceAll(arena, patched, java_file_check_line, root_file_check_line);
    patched = try replaceAll(arena, patched, old_local_properties_block, new_local_properties_block);
    patched = try ensureCompatibilityBlock(arena, patched);
    patched = try ensureLocalPropertiesProbe(arena, patched);
    return patched;
}

/// Inserts missing compatibility helper blocks before ABI task suffix function.
fn ensureCompatibilityBlock(
    arena: std.mem.Allocator,
    source: []const u8,
) ![]const u8 {
    const has_optimize_block = std.mem.indexOf(u8, source, optimize_marker) != null;
    const has_zig_discovery_block = std.mem.indexOf(u8, source, zig_discovery_marker) != null;
    if (has_optimize_block and has_zig_discovery_block) return source;

    const marker_idx = std.mem.indexOf(u8, source, abi_suffix_marker) orelse return source;

    var insertion = std.ArrayList(u8).empty;
    defer insertion.deinit(arena);
    if (!has_optimize_block) try insertion.appendSlice(arena, optimize_block);
    if (!has_zig_discovery_block) try insertion.appendSlice(arena, zig_discovery_block);

    return std.fmt.allocPrint(arena, "{s}{s}{s}", .{
        source[0..marker_idx],
        insertion.items,
        source[marker_idx..],
    });
}

/// Ensures Zig discovery checks `local.properties` before PATH probing.
///
/// This is needed for Android Studio launches where shell PATH does not include
/// toolchain manager shims, but projects can still provide stable local
/// overrides through `wizig.zig.bin`.
fn ensureLocalPropertiesProbe(
    arena: std.mem.Allocator,
    source: []const u8,
) ![]const u8 {
    if (std.mem.indexOf(u8, source, local_properties_probe_marker) != null) return source;
    const path_probe_idx = std.mem.indexOf(u8, source, path_probe_marker) orelse return source;
    return std.fmt.allocPrint(arena, "{s}{s}{s}", .{
        source[0..path_probe_idx],
        new_local_properties_block,
        source[path_probe_idx..],
    });
}

/// Replaces all exact occurrences of `needle` with `replacement`.
///
/// Returns the original slice when no matches exist, preserving allocation and
/// making idempotent checks straightforward for callers.
fn replaceAll(
    arena: std.mem.Allocator,
    source: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]const u8 {
    const first_idx = std.mem.indexOf(u8, source, needle) orelse return source;

    var out = std.ArrayList(u8).empty;
    var cursor: usize = 0;
    var next_idx: usize = first_idx;

    while (true) {
        try out.appendSlice(arena, source[cursor..next_idx]);
        try out.appendSlice(arena, replacement);
        cursor = next_idx + needle.len;
        next_idx = std.mem.indexOfPos(u8, source, cursor, needle) orelse break;
    }
    try out.appendSlice(arena, source[cursor..]);
    return out.toOwnedSlice(arena);
}

test "patchBuildGradleKtsText migrates jniLibs directories entry to .path" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "sourceSets {\n" ++
        "    getByName(\"main\") {\n" ++
        "        jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\"))\n" ++
        "    }\n" ++
        "}\n";
    const output = try patchBuildGradleKtsText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, old_jni_libs_line) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, new_jni_libs_line) != null);
}

test "patchBuildGradleKtsText injects Zig discovery and optimize blocks" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "val wizigAbiTargets: Map<String, String> = mapOf(\n" ++
        "    \"arm64-v8a\" to \"aarch64-linux-android\",\n" ++
        ")\n\n" ++
        "fun abiTaskSuffix(abi: String): String = abi\n\n" ++
        "tasks.register<Exec>(\"buildWizigFfiArm64V8a\") {\n" ++
        "    commandLine(\n" ++
        "            \"zig\",\n" ++
        "            \"build-lib\",\n" ++
        "            \"-OReleaseFast\",\n" ++
        "    )\n" ++
        "}\n";
    const output = try patchBuildGradleKtsText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, zig_discovery_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, optimize_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, new_zig_command_line) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, new_optimize_line) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line.startsWith(\"wizig.zig.bin=\")") != null);
}

test "patchBuildGradleKtsText migrates inline commandLine zig invocations" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "fun abiTaskSuffix(abi: String): String = abi\n\n" ++
        "tasks.register<Exec>(\"buildWizigFfiArm64V8a\") {\n" ++
        "    commandLine(\"zig\", \"build-lib\", \"-OReleaseFast\", \"--name\", \"wizigffi\")\n" ++
        "}\n";
    const output = try patchBuildGradleKtsText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, "commandLine(discoverWizigZigBinary(),") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"-O${requestedWizigOptimize}\"") != null);
}

test "patchBuildGradleKtsText is idempotent for already migrated text" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        optimize_block ++
        zig_discovery_block ++
        "sourceSets {\n" ++
        "    getByName(\"main\") {\n" ++
        "        jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\").path)\n" ++
        "    }\n" ++
        "}\n";
    const output = try patchBuildGradleKtsText(arena, input);

    try std.testing.expectEqualStrings(input, output);
}

test "patchBuildGradleKtsText leaves unrelated content unchanged" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "android {\n" ++
        "    defaultConfig {\n" ++
        "        minSdk = 26\n" ++
        "    }\n" ++
        "}\n";
    const output = try patchBuildGradleKtsText(arena, input);

    try std.testing.expectEqualStrings(input, output);
}
