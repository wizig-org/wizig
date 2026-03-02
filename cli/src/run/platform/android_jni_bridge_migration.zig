//! Android JNI bridge compatibility migration for Zig print forwarding.
//!
//! ## Problem
//! Generated JNI bridge files historically did not forward native
//! `stdout`/`stderr` to Android logcat. As a result, `std.debug.print` output
//! from Zig code was often invisible during `wizig run` log monitoring.
//!
//! ## Scope
//! This migration patches `.wizig/generated/android/jni/WizigGeneratedApiBridge.c`
//! in-place when needed:
//! - adds Android-only headers (`android/log.h`, `pthread.h`, `unistd.h`)
//! - injects a one-time stdio-to-logcat forwarder helper
//! - calls the helper during binding validation
//!
//! ## Safety
//! Rewrites are idempotent and limited to known generated anchors. User host
//! sources are not modified.
const std = @import("std");

const fs_utils = @import("fs_utils.zig");

/// Result metadata for generated JNI bridge migration.
pub const MigrationSummary = struct {
    /// True when generated JNI bridge file existed and was inspected.
    inspected: bool = false,
    /// True when migration rewrites were applied and persisted.
    patched: bool = false,
};

const generated_bridge_relative_path = ".wizig/generated/android/jni/WizigGeneratedApiBridge.c";

const include_anchor = "#include <dlfcn.h>\n\n";
const include_replacement =
    "#include <dlfcn.h>\n" ++
    "#if defined(__ANDROID__)\n" ++
    "#include <android/log.h>\n" ++
    "#include <pthread.h>\n" ++
    "#include <unistd.h>\n" ++
    "#endif\n\n";

const helper_insert_anchor = "static void copy_slice_to_buffer";
const helper_marker = "static void wizig_forward_stdio_to_logcat_once(void)";
const helper_block =
    "#if defined(__ANDROID__)\n" ++
    "static pthread_once_t wizig_stdio_forward_once = PTHREAD_ONCE_INIT;\n\n" ++
    "static void* wizig_android_stdio_forward_loop(void* ctx) {\n" ++
    "    int read_fd = *(int*)ctx;\n" ++
    "    free(ctx);\n" ++
    "    char buffer[1024];\n" ++
    "    while (true) {\n" ++
    "        ssize_t read_count = read(read_fd, buffer, sizeof(buffer) - 1);\n" ++
    "        if (read_count <= 0) break;\n" ++
    "        buffer[(size_t)read_count] = '\\0';\n" ++
    "        __android_log_write(ANDROID_LOG_INFO, \"WizigZig\", buffer);\n" ++
    "    }\n" ++
    "    close(read_fd);\n" ++
    "    return NULL;\n" ++
    "}\n\n" ++
    "static void wizig_android_setup_stdio_forwarder(void) {\n" ++
    "    int pipe_fds[2];\n" ++
    "    if (pipe(pipe_fds) != 0) return;\n" ++
    "    const int read_fd = pipe_fds[0];\n" ++
    "    const int write_fd = pipe_fds[1];\n\n" ++
    "    if (dup2(write_fd, STDOUT_FILENO) < 0 || dup2(write_fd, STDERR_FILENO) < 0) {\n" ++
    "        close(read_fd);\n" ++
    "        close(write_fd);\n" ++
    "        return;\n" ++
    "    }\n\n" ++
    "    close(write_fd);\n" ++
    "    setvbuf(stdout, NULL, _IONBF, 0);\n" ++
    "    setvbuf(stderr, NULL, _IONBF, 0);\n\n" ++
    "    int* thread_fd = (int*)malloc(sizeof(int));\n" ++
    "    if (thread_fd == NULL) {\n" ++
    "        close(read_fd);\n" ++
    "        return;\n" ++
    "    }\n" ++
    "    *thread_fd = read_fd;\n\n" ++
    "    pthread_t thread;\n" ++
    "    if (pthread_create(&thread, NULL, wizig_android_stdio_forward_loop, thread_fd) != 0) {\n" ++
    "        free(thread_fd);\n" ++
    "        close(read_fd);\n" ++
    "        return;\n" ++
    "    }\n" ++
    "    pthread_detach(thread);\n" ++
    "}\n\n" ++
    "static void wizig_forward_stdio_to_logcat_once(void) {\n" ++
    "    pthread_once(&wizig_stdio_forward_once, wizig_android_setup_stdio_forwarder);\n" ++
    "}\n" ++
    "#else\n" ++
    "static void wizig_forward_stdio_to_logcat_once(void) {\n" ++
    "}\n" ++
    "#endif\n\n";

const validate_anchor =
    "JNIEXPORT void JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_wizig_1validate_1bindings(JNIEnv* env, jclass clazz) {\n" ++
    "    (void)clazz;\n";
const validate_replacement =
    "JNIEXPORT void JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_wizig_1validate_1bindings(JNIEnv* env, jclass clazz) {\n" ++
    "    (void)clazz;\n" ++
    "    wizig_forward_stdio_to_logcat_once();\n";
const validate_call_marker =
    "JNIEXPORT void JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_wizig_1validate_1bindings(JNIEnv* env, jclass clazz) {\n" ++
    "    (void)clazz;\n" ++
    "    wizig_forward_stdio_to_logcat_once();\n";

/// Ensures generated Android JNI bridge supports native stdio forwarding.
pub fn ensureGeneratedJniBridgeCompatibility(
    arena: std.mem.Allocator,
    io: std.Io,
    project_dir: []const u8,
) !MigrationSummary {
    const bridge_path = try fs_utils.joinPath(arena, project_dir, generated_bridge_relative_path);
    if (!fs_utils.pathExists(io, bridge_path)) return .{};

    const original = try std.Io.Dir.cwd().readFileAlloc(io, bridge_path, arena, .limited(4 * 1024 * 1024));
    const patched = try patchGeneratedBridgeText(arena, original);
    if (std.mem.eql(u8, original, patched)) {
        return .{ .inspected = true, .patched = false };
    }

    try fs_utils.writeFileAtomically(io, bridge_path, patched);
    return .{ .inspected = true, .patched = true };
}

/// Applies idempotent text migrations to generated JNI bridge source.
fn patchGeneratedBridgeText(
    arena: std.mem.Allocator,
    source: []const u8,
) ![]const u8 {
    var patched = source;
    patched = try ensureAndroidIncludes(arena, patched);
    patched = try ensureStdIoHelper(arena, patched);
    patched = try ensureValidationHook(arena, patched);
    return patched;
}

/// Adds Android-specific include set when missing.
fn ensureAndroidIncludes(
    arena: std.mem.Allocator,
    source: []const u8,
) ![]const u8 {
    if (std.mem.indexOf(u8, source, "#include <android/log.h>") != null) return source;
    return replaceFirst(arena, source, include_anchor, include_replacement);
}

/// Injects stdio forwarding helper block ahead of bridge utility functions.
fn ensureStdIoHelper(
    arena: std.mem.Allocator,
    source: []const u8,
) ![]const u8 {
    if (std.mem.indexOf(u8, source, helper_marker) != null) return source;
    const anchor_idx = std.mem.indexOf(u8, source, helper_insert_anchor) orelse return source;
    return std.fmt.allocPrint(arena, "{s}{s}{s}", .{
        source[0..anchor_idx],
        helper_block,
        source[anchor_idx..],
    });
}

/// Calls stdio forwarder during JNI binding validation initialization.
fn ensureValidationHook(
    arena: std.mem.Allocator,
    source: []const u8,
) ![]const u8 {
    if (std.mem.indexOf(u8, source, validate_call_marker) != null) return source;
    return replaceFirst(arena, source, validate_anchor, validate_replacement);
}

/// Replaces the first exact occurrence of `needle` with `replacement`.
fn replaceFirst(
    arena: std.mem.Allocator,
    source: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]const u8 {
    const idx = std.mem.indexOf(u8, source, needle) orelse return source;
    return std.fmt.allocPrint(arena, "{s}{s}{s}", .{
        source[0..idx],
        replacement,
        source[idx + needle.len ..],
    });
}

test "patchGeneratedBridgeText injects include, helper, and validation hook" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "#include <stdio.h>\n" ++
        "#include <dlfcn.h>\n\n" ++
        "static void copy_slice_to_buffer(const uint8_t* ptr, size_t len, char* out, size_t cap) {\n" ++
        "}\n\n" ++
        "JNIEXPORT void JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_wizig_1validate_1bindings(JNIEnv* env, jclass clazz) {\n" ++
        "    (void)clazz;\n" ++
        "}\n";
    const output = try patchGeneratedBridgeText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, "#include <android/log.h>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, helper_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "wizig_forward_stdio_to_logcat_once();") != null);
}

test "patchGeneratedBridgeText is idempotent for already migrated bridge" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        include_replacement ++
        helper_block ++
        "static void copy_slice_to_buffer(const uint8_t* ptr, size_t len, char* out, size_t cap) {\n" ++
        "}\n\n" ++
        validate_replacement ++
        "}\n";
    const output = try patchGeneratedBridgeText(arena, input);

    try std.testing.expectEqualStrings(input, output);
}

test "patchGeneratedBridgeText leaves unrelated source unchanged" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input = "int main(void) { return 0; }\n";
    const output = try patchGeneratedBridgeText(arena, input);

    try std.testing.expectEqualStrings(input, output);
}
