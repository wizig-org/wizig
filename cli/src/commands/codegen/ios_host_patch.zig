//! iOS host project patching for direct Xcode FFI builds.
//!
//! ## Problem
//! Direct Xcode builds do not run `wizig run`, so host projects can miss
//! per-app FFI packaging updates unless codegen patches build wiring.
//!
//! ## Approach
//! This module patches generated host `.xcodeproj/project.pbxproj` files with a
//! deterministic `PBXShellScriptBuildPhase` that builds and embeds a framework
//! artifact and mirrors it into a generated `.xcframework`.
//!
//! ## Safety
//! Patching is idempotent: if the phase already exists, no changes are written.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../../support/fs.zig");
const ios_host_phase_entry = @import("ios_host_phase_entry.zig");
const path_util = @import("../../support/path.zig");

/// Summary of iOS host project patching work performed in one codegen pass.
pub const PatchSummary = struct {
    /// Number of discovered `.xcodeproj` files scanned for migration.
    scanned_projects: usize = 0,
    /// Number of project files updated with new build phase wiring.
    patched_projects: usize = 0,
};

const phase_name = ios_host_phase_entry.phase_name;
const phase_id = ios_host_phase_entry.phase_id;
const phase_ref_line = ios_host_phase_entry.phase_ref_line;
const phase_entry = ios_host_phase_entry.phase_entry;

const section_markers = struct {
    const begin_shell = "/* Begin PBXShellScriptBuildPhase section */";
    const end_shell = "/* End PBXShellScriptBuildPhase section */";
    const begin_sources = "/* Begin PBXSourcesBuildPhase section */";
};

/// Ensures all discovered iOS host projects include Wizig's FFI build phase.
pub fn ensureIosHostBuildPhase(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !PatchSummary {
    const ios_dir = try path_util.join(arena, project_root, "ios");
    if (!fs_util.pathExists(io, ios_dir)) return .{};

    var result: PatchSummary = .{};
    var ios = std.Io.Dir.cwd().openDir(io, ios_dir, .{ .iterate = true }) catch return result;
    defer ios.close(io);

    var walker = try ios.walk(arena);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.endsWith(u8, entry.path, ".xcodeproj")) continue;

        result.scanned_projects += 1;
        const pbx_path = try std.fmt.allocPrint(arena, "{s}{s}{s}{s}project.pbxproj", .{
            ios_dir,
            std.fs.path.sep_str,
            entry.path,
            std.fs.path.sep_str,
        });
        if (!fs_util.pathExists(io, pbx_path)) continue;

        const changed = try patchProjectFile(arena, io, pbx_path);
        if (changed) result.patched_projects += 1;
    }

    return result;
}

fn patchProjectFile(arena: std.mem.Allocator, io: std.Io, pbx_path: []const u8) !bool {
    const original = try std.Io.Dir.cwd().readFileAlloc(io, pbx_path, arena, .limited(8 * 1024 * 1024));
    const patched = try patchProjectText(arena, original);
    if (std.mem.eql(u8, original, patched)) return false;
    return fs_util.writeFileIfChanged(arena, io, pbx_path, patched);
}

fn patchProjectText(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    const with_section = try upsertShellSection(arena, text);
    const with_ref = try injectAppBuildPhaseReference(arena, with_section);
    return try disableUserScriptSandboxing(arena, with_ref);
}

fn upsertShellSection(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    const phase_start_marker = "\t\t" ++ phase_id ++ " /* " ++ phase_name ++ " */ = {\n";
    if (std.mem.indexOf(u8, text, phase_start_marker)) |start_idx| {
        const end_rel = std.mem.indexOf(u8, text[start_idx..], "\t\t};\n") orelse return error.InvalidPbxproj;
        const end_idx = start_idx + end_rel + "\t\t};\n".len;
        return try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
            text[0..start_idx],
            phase_entry,
            text[end_idx..],
        });
    }

    if (std.mem.indexOf(u8, text, section_markers.begin_shell) != null) {
        const end_idx = std.mem.indexOf(u8, text, section_markers.end_shell) orelse return error.InvalidPbxproj;
        return try std.fmt.allocPrint(arena, "{s}{s}\n{s}", .{
            text[0..end_idx],
            phase_entry,
            text[end_idx..],
        });
    }

    const marker_idx = std.mem.indexOf(u8, text, section_markers.begin_sources) orelse return error.InvalidPbxproj;
    const shell_block = section_markers.begin_shell ++ "\n" ++ phase_entry ++ section_markers.end_shell ++ "\n\n";
    return try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
        text[0..marker_idx],
        shell_block,
        text[marker_idx..],
    });
}

fn injectAppBuildPhaseReference(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    const app_product_type = "productType = \"com.apple.product-type.application\";";
    const app_idx = std.mem.indexOf(u8, text, app_product_type) orelse return error.InvalidPbxproj;
    const phase_open_marker = "buildPhases = (\n";

    const open_idx = std.mem.lastIndexOf(u8, text[0..app_idx], phase_open_marker) orelse return error.InvalidPbxproj;
    const after_open = open_idx + phase_open_marker.len;
    const close_rel = std.mem.indexOf(u8, text[after_open..], "\t\t\t);\n") orelse return error.InvalidPbxproj;
    const close_idx = after_open + close_rel;
    const block = text[after_open..close_idx];
    if (std.mem.indexOf(u8, block, phase_id) != null or std.mem.indexOf(u8, block, phase_name) != null) return text;

    return try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
        text[0..close_idx],
        phase_ref_line,
        text[close_idx..],
    });
}

fn disableUserScriptSandboxing(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    const needle = "ENABLE_USER_SCRIPT_SANDBOXING = YES;";
    const replacement = "ENABLE_USER_SCRIPT_SANDBOXING = NO;";
    if (std.mem.indexOf(u8, text, needle) == null) return text;

    var out = std.ArrayList(u8).empty;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, text, cursor, needle)) |idx| {
        try out.appendSlice(arena, text[cursor..idx]);
        try out.appendSlice(arena, replacement);
        cursor = idx + needle.len;
    }
    try out.appendSlice(arena, text[cursor..]);
    return out.toOwnedSlice(arena);
}

test "patchProjectText injects shell section and app build phase reference" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "/* Begin PBXNativeTarget section */\n" ++
        "\t\tAPP /* App */ = {\n" ++
        "\t\t\tbuildPhases = (\n" ++
        "\t\t\t\tSRC /* Sources */,\n" ++
        "\t\t\t\tFRM /* Frameworks */,\n" ++
        "\t\t\t\tRES /* Resources */,\n" ++
        "\t\t\t);\n" ++
        "\t\t\tproductType = \"com.apple.product-type.application\";\n" ++
        "\t\t};\n" ++
        "/* End PBXNativeTarget section */\n\n" ++
        "/* Begin PBXSourcesBuildPhase section */\n" ++
        "/* End PBXSourcesBuildPhase section */\n";

    const output = try patchProjectText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, section_markers.begin_shell) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, phase_name) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, phase_ref_line) != null);
}

test "patchProjectText is idempotent when phase already present" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "/* Begin PBXShellScriptBuildPhase section */\n" ++
        phase_entry ++
        "/* End PBXShellScriptBuildPhase section */\n\n" ++
        "/* Begin PBXNativeTarget section */\n" ++
        "\t\tAPP /* App */ = {\n" ++
        "\t\t\tbuildPhases = (\n" ++
        phase_ref_line ++
        "\t\t\t);\n" ++
        "\t\t\tproductType = \"com.apple.product-type.application\";\n" ++
        "\t\t};\n" ++
        "/* End PBXNativeTarget section */\n";

    const output = try patchProjectText(arena, input);

    try std.testing.expectEqualStrings(input, output);
}

test "phase_entry includes Zig discovery fallback locations" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, ".zvm/master/zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "/opt/homebrew/bin/zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "ZIG_BINARY") != null);
}

test "phase_entry configures zig caches inside xcode temp directories" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "TARGET_TEMP_DIR") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "ZIG_LOCAL_CACHE_DIR") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "ZIG_GLOBAL_CACHE_DIR") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "TMP_FRAMEWORK_BIN") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WIZIG_FFI_OPTIMIZE") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WizigFFI.xcframework") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "_CodeSignature/CodeResources") != null);
}

test "phase_entry signs device framework outputs when code signing is enabled" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "EXPANDED_CODE_SIGN_IDENTITY") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "EXPANDED_CODE_SIGN_IDENTITY_NAME") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "CODE_SIGN_IDENTITY") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "/usr/bin/codesign --force --sign") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "CODE_SIGNING_ALLOWED") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "-headerpad_max_install_names") != null);
}

test "phase_entry assigns framework bundle identifier distinct from app" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "FRAMEWORK_BUNDLE_ID") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "PRODUCT_BUNDLE_IDENTIFIER") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, ".wizigffi") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "<string>dev.wizig.WizigFFI</string>") == null);
}

test "disableUserScriptSandboxing rewrites yes to no" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "ENABLE_USER_SCRIPT_SANDBOXING = YES;\n" ++
        "ENABLE_USER_SCRIPT_SANDBOXING = YES;\n";
    const output = try disableUserScriptSandboxing(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, "ENABLE_USER_SCRIPT_SANDBOXING = YES;") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ENABLE_USER_SCRIPT_SANDBOXING = NO;") != null);
}
