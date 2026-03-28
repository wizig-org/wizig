//! In-memory Android Gradle build script migration helpers.
const std = @import("std");

pub const old_jni_libs_line =
    "jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\"))";
pub const new_jni_libs_line =
    "jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\").path)";
pub const old_zig_command_line = "            \"zig\",\n";
pub const new_zig_command_line = "            discoverWizigZigBinary(),\n";
pub const old_zig_command_inline = "commandLine(\"zig\",";
pub const new_zig_command_inline = "commandLine(discoverWizigZigBinary(),";
pub const old_optimize_line = "            \"-OReleaseFast\",\n";
pub const new_optimize_line = "            \"-O${requestedWizigOptimize}\",\n";
pub const old_optimize_inline = "\"-OReleaseFast\",";
pub const new_optimize_inline = "\"-O${requestedWizigOptimize}\",";
pub const malformed_optimize_error_line =
    "        \"Unsupported Wizig FFI optimize mode '${requestedWizigOptimize}'. Supported values: ${supportedWizigOptimizeModes.joinToString(\\\", \\\")}\"\n";
pub const fixed_optimize_error_line =
    "        \"Unsupported Wizig FFI optimize mode '${requestedWizigOptimize}'. Supported values: ${supportedWizigOptimizeModes.joinToString(\", \")}\"\n";
pub const java_file_check_line = "        if (java.io.File(candidate).canExecute()) return candidate\n";
pub const root_file_check_line = "        if (rootProject.file(candidate).canExecute()) return candidate\n";
pub const old_local_properties_block =
    "    val localProperties = java.util.Properties()\n" ++
    "    val localPropertiesFile = rootProject.file(\"local.properties\")\n" ++
    "    if (localPropertiesFile.isFile) {\n" ++
    "        runCatching {\n" ++
    "            localPropertiesFile.inputStream().use { stream -> localProperties.load(stream) }\n" ++
    "            val fromLocalProperties = localProperties.getProperty(\"wizig.zig.bin\")?.trim()\n" ++
    "            if (!fromLocalProperties.isNullOrBlank()) return fromLocalProperties\n" ++
    "        }\n" ++
    "    }\n\n";
pub const new_local_properties_block =
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

pub const abi_suffix_marker = "fun abiTaskSuffix(abi: String): String =";
pub const optimize_marker = "val requestedWizigOptimize: String =";
pub const zig_discovery_marker = "fun discoverWizigZigBinary(): String {";
const local_properties_probe_marker = "    val localPropertiesFile = rootProject.file(\"local.properties\")\n";
const path_probe_marker = "    val pathProbe = runCatching {\n";

pub const optimize_block =
    "val supportedWizigOptimizeModes: Set<String> = setOf(\"Debug\", \"ReleaseFast\", \"ReleaseSafe\", \"ReleaseSmall\")\n\n" ++
    "val requestedWizigOptimize: String = providers.gradleProperty(\"wizig.ffi.optimize\").orNull ?: \"Debug\"\n" ++
    "if (requestedWizigOptimize !in supportedWizigOptimizeModes) {\n" ++
    "    throw org.gradle.api.GradleException(\n" ++
    "        \"Unsupported Wizig FFI optimize mode '${requestedWizigOptimize}'. Supported values: ${supportedWizigOptimizeModes.joinToString(\", \")}\"\n" ++
    "    )\n" ++
    "}\n\n";

pub const zig_discovery_block =
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

/// Applies in-memory text migrations for `build.gradle.kts`.
pub fn patchBuildGradleKtsText(
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
