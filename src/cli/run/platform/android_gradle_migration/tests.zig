const std = @import("std");
const patch = @import("patch.zig");

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
    const output = try patch.patchBuildGradleKtsText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, patch.old_jni_libs_line) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, patch.new_jni_libs_line) != null);
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
    const output = try patch.patchBuildGradleKtsText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, patch.zig_discovery_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, patch.optimize_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, patch.new_zig_command_line) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, patch.new_optimize_line) != null);
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
    const output = try patch.patchBuildGradleKtsText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, "commandLine(discoverWizigZigBinary(),") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"-O${requestedWizigOptimize}\"") != null);
}

test "patchBuildGradleKtsText migrates local properties probing and remains idempotent" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        patch.optimize_block ++
        patch.zig_discovery_block ++
        patch.old_local_properties_block ++
        "sourceSets {\n" ++
        "    getByName(\"main\") {\n" ++
        "        jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\").path)\n" ++
        "    }\n" ++
        "}\n";
    const output = try patch.patchBuildGradleKtsText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, patch.new_local_properties_block) != null);
    try std.testing.expectEqualStrings(
        patch.optimize_block ++
            patch.zig_discovery_block ++
            patch.new_local_properties_block ++
            "sourceSets {\n" ++
            "    getByName(\"main\") {\n" ++
            "        jniLibs.directories.add(rootProject.file(\"../.wizig/generated/android/jniLibs\").path)\n" ++
            "    }\n" ++
            "}\n",
        output,
    );
}
