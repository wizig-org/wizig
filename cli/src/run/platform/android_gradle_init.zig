//! Gradle init-script generation for Android run compatibility.
//!
//! ## Why This Exists
//! Existing app projects may contain legacy host build wiring where
//! `merge*JniLibFolders` consumes outputs from `buildWizigFfi*` tasks without an
//! explicit dependency edge. Modern Gradle versions flag this as an error.
//!
//! ## Strategy
//! `wizig run android` passes a generated init script (`-I`) that injects
//! dependencies from JNI merge tasks to Wizig FFI build tasks for all
//! subprojects. This preserves backward compatibility without mutating user
//! build files.
const std = @import("std");

const fs_utils = @import("fs_utils.zig");

/// Writes/updates the Gradle init script used by Android run orchestration.
///
/// The script path lives under `gradle_home` to keep lifecycle coupled with
/// Gradle cache cleanup strategy used by `wizig run`.
pub fn ensureInitScript(
    arena: std.mem.Allocator,
    io: std.Io,
    gradle_home: []const u8,
) ![]const u8 {
    const script_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}wizig-run-init.gradle",
        .{ gradle_home, std.fs.path.sep_str },
    );
    try fs_utils.writeFileAtomically(io, script_path, init_script_contents);
    return script_path;
}

/// Static Gradle init script used to wire legacy task dependencies.
pub const init_script_contents =
    "allprojects { project ->\n" ++
    "    project.tasks.matching { task ->\n" ++
    "        task.name.startsWith(\"merge\") && task.name.endsWith(\"JniLibFolders\")\n" ++
    "    }.configureEach { mergeTask ->\n" ++
    "        def wizigTasks = project.tasks.matching { task -> task.name.startsWith(\"buildWizigFfi\") }\n" ++
    "        mergeTask.dependsOn(wizigTasks)\n" ++
    "    }\n" ++
    "}\n";

test "init script content wires merge JNI tasks to Wizig FFI producers" {
    try std.testing.expect(std.mem.indexOf(u8, init_script_contents, "merge") != null);
    try std.testing.expect(std.mem.indexOf(u8, init_script_contents, "JniLibFolders") != null);
    try std.testing.expect(std.mem.indexOf(u8, init_script_contents, "buildWizigFfi") != null);
    try std.testing.expect(std.mem.indexOf(u8, init_script_contents, "dependsOn") != null);
}
