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
    return try disableUserScriptSandboxingForAppTarget(arena, with_ref);
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

/// Disables user script sandboxing only for the app target build configurations.
///
/// Invariant: project- or test-target configurations must remain untouched.
fn disableUserScriptSandboxingForAppTarget(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    const app_product_type = "productType = \"com.apple.product-type.application\";";
    const app_idx = std.mem.indexOf(u8, text, app_product_type) orelse return error.InvalidPbxproj;
    const build_config_list_marker = "buildConfigurationList = ";
    const list_idx = std.mem.lastIndexOf(u8, text[0..app_idx], build_config_list_marker) orelse return error.InvalidPbxproj;
    const list_id_start = list_idx + build_config_list_marker.len;
    const list_id_end_rel = std.mem.indexOfAny(u8, text[list_id_start..], " ;\n\t") orelse return error.InvalidPbxproj;
    const config_list_id = std.mem.trim(u8, text[list_id_start .. list_id_start + list_id_end_rel], " \t");
    if (config_list_id.len == 0) return error.InvalidPbxproj;

    var config_ids = try appTargetBuildConfigIds(arena, text, config_list_id);
    if (config_ids.items.len == 0) return error.InvalidPbxproj;

    var updated = text;
    for (config_ids.items) |config_id| {
        updated = try upsertUserScriptSandboxingNoForConfig(arena, updated, config_id);
    }
    return updated;
}

/// Collects XCBuildConfiguration ids listed by one XCConfigurationList.
fn appTargetBuildConfigIds(
    arena: std.mem.Allocator,
    text: []const u8,
    config_list_id: []const u8,
) !std.ArrayList([]const u8) {
    var out = std.ArrayList([]const u8).empty;

    const object_prefix = try std.fmt.allocPrint(arena, "\t\t{s} /* ", .{config_list_id});
    const object_start = std.mem.indexOf(u8, text, object_prefix) orelse return error.InvalidPbxproj;
    const object_end_rel = std.mem.indexOf(u8, text[object_start..], "\t\t};\n") orelse return error.InvalidPbxproj;
    const object_end = object_start + object_end_rel + "\t\t};\n".len;
    const object_slice = text[object_start..object_end];

    const configs_marker = "buildConfigurations = (\n";
    const configs_start_rel = std.mem.indexOf(u8, object_slice, configs_marker) orelse return error.InvalidPbxproj;
    const configs_start = object_start + configs_start_rel + configs_marker.len;
    const configs_end_rel = std.mem.indexOf(u8, text[configs_start..object_end], "\t\t\t);\n") orelse return error.InvalidPbxproj;
    const configs_end = configs_start + configs_end_rel;

    var lines = std.mem.splitScalar(u8, text[configs_start..configs_end], '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;
        const id_end = std.mem.indexOfAny(u8, trimmed, " \t,") orelse trimmed.len;
        if (id_end == 0) continue;
        const id_copy = try arena.dupe(u8, trimmed[0..id_end]);
        try out.append(arena, id_copy);
    }
    return out;
}

/// Ensures one XCBuildConfiguration object has `ENABLE_USER_SCRIPT_SANDBOXING = NO`.
fn upsertUserScriptSandboxingNoForConfig(
    arena: std.mem.Allocator,
    text: []const u8,
    config_id: []const u8,
) ![]const u8 {
    const object_prefix = try std.fmt.allocPrint(arena, "\t\t{s} /* ", .{config_id});
    const object_start = std.mem.indexOf(u8, text, object_prefix) orelse return error.InvalidPbxproj;
    const object_end_rel = std.mem.indexOf(u8, text[object_start..], "\t\t};\n") orelse return error.InvalidPbxproj;
    const object_end = object_start + object_end_rel + "\t\t};\n".len;
    const object_slice = text[object_start..object_end];

    const build_settings_marker = "buildSettings = {\n";
    const build_start_rel = std.mem.indexOf(u8, object_slice, build_settings_marker) orelse return error.InvalidPbxproj;
    const build_start = object_start + build_start_rel + build_settings_marker.len;
    const build_end_rel = std.mem.indexOf(u8, text[build_start..object_end], "\t\t\t};\n") orelse return error.InvalidPbxproj;
    const build_end = build_start + build_end_rel;
    const build_slice = text[build_start..build_end];

    const disabled = "ENABLE_USER_SCRIPT_SANDBOXING = NO;";
    if (std.mem.indexOf(u8, build_slice, disabled) != null) return text;

    const enabled = "ENABLE_USER_SCRIPT_SANDBOXING = YES;";
    if (std.mem.indexOf(u8, build_slice, enabled)) |enabled_rel| {
        const enabled_start = build_start + enabled_rel;
        return try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
            text[0..enabled_start],
            disabled,
            text[enabled_start + enabled.len ..],
        });
    }

    const insertion = "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n";
    return try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
        text[0..build_end],
        insertion,
        text[build_end..],
    });
}

test "patchProjectText injects shell section and app build phase reference" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "/* Begin PBXNativeTarget section */\n" ++
        "\t\tAPP /* App */ = {\n" ++
        "\t\t\tbuildConfigurationList = APP_CFG_LIST /* Build configuration list for PBXNativeTarget \"App\" */;\n" ++
        "\t\t\tbuildPhases = (\n" ++
        "\t\t\t\tSRC /* Sources */,\n" ++
        "\t\t\t\tFRM /* Frameworks */,\n" ++
        "\t\t\t\tRES /* Resources */,\n" ++
        "\t\t\t);\n" ++
        "\t\t\tproductType = \"com.apple.product-type.application\";\n" ++
        "\t\t};\n" ++
        "/* End PBXNativeTarget section */\n\n" ++
        "/* Begin XCBuildConfiguration section */\n" ++
        "\t\tAPP_DEBUG /* Debug */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Debug;\n" ++
        "\t\t};\n" ++
        "\t\tAPP_RELEASE /* Release */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Release;\n" ++
        "\t\t};\n" ++
        "/* End XCBuildConfiguration section */\n\n" ++
        "/* Begin XCConfigurationList section */\n" ++
        "\t\tAPP_CFG_LIST /* Build configuration list for PBXNativeTarget \"App\" */ = {\n" ++
        "\t\t\tisa = XCConfigurationList;\n" ++
        "\t\t\tbuildConfigurations = (\n" ++
        "\t\t\t\tAPP_DEBUG /* Debug */,\n" ++
        "\t\t\t\tAPP_RELEASE /* Release */,\n" ++
        "\t\t\t);\n" ++
        "\t\t\tdefaultConfigurationIsVisible = 0;\n" ++
        "\t\t\tdefaultConfigurationName = Release;\n" ++
        "\t\t};\n" ++
        "/* End XCConfigurationList section */\n\n" ++
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
        "\t\t\tbuildConfigurationList = APP_CFG_LIST /* Build configuration list for PBXNativeTarget \"App\" */;\n" ++
        "\t\t\tbuildPhases = (\n" ++
        phase_ref_line ++
        "\t\t\t);\n" ++
        "\t\t\tproductType = \"com.apple.product-type.application\";\n" ++
        "\t\t};\n" ++
        "/* End PBXNativeTarget section */\n\n" ++
        "/* Begin XCBuildConfiguration section */\n" ++
        "\t\tAPP_DEBUG /* Debug */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Debug;\n" ++
        "\t\t};\n" ++
        "\t\tAPP_RELEASE /* Release */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Release;\n" ++
        "\t\t};\n" ++
        "/* End XCBuildConfiguration section */\n\n" ++
        "/* Begin XCConfigurationList section */\n" ++
        "\t\tAPP_CFG_LIST /* Build configuration list for PBXNativeTarget \"App\" */ = {\n" ++
        "\t\t\tisa = XCConfigurationList;\n" ++
        "\t\t\tbuildConfigurations = (\n" ++
        "\t\t\t\tAPP_DEBUG /* Debug */,\n" ++
        "\t\t\t\tAPP_RELEASE /* Release */,\n" ++
        "\t\t\t);\n" ++
        "\t\t\tdefaultConfigurationIsVisible = 0;\n" ++
        "\t\t\tdefaultConfigurationName = Release;\n" ++
        "\t\t};\n" ++
        "/* End XCConfigurationList section */\n";

    const output = try patchProjectText(arena, input);

    try std.testing.expectEqualStrings(input, output);
}

test "phase_entry includes Zig discovery fallback locations" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, ".zvm/master/zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "/opt/homebrew/bin/zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "ZIG_BINARY") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, ".wizig/toolchain.lock.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WIZIG_ZIG_AUTO_INSTALL") != null);
}

test "phase_entry configures zig caches inside xcode temp directories" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "TARGET_TEMP_DIR") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "ZIG_LOCAL_CACHE_DIR") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "ZIG_GLOBAL_CACHE_DIR") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "TMP_DEVICE_FRAMEWORK_BIN") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "TMP_SIM_ARM64_FRAMEWORK_BIN") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WIZIG_FFI_OPTIMIZE") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WIZIG_FFI_ALLOW_OPTIMIZE_OVERRIDE") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WIZIG_FFI_ALLOW_TOOLCHAIN_DRIFT") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WizigFFI.xcframework") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "_CodeSignature/CodeResources") != null);
}

test "phase_entry builds device and simulator xcframework slices" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "xcrun --sdk iphoneos --show-sdk-path") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "xcrun --sdk iphonesimulator --show-sdk-path") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "build_ffi_slice \\\"aarch64-ios\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "build_ffi_slice \\\"aarch64-ios-simulator\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "build_ffi_slice \\\"x86_64-ios-simulator\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "xcrun lipo -create") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "-framework \\\"${TMP_DEVICE_FRAMEWORK_DIR}\\\" -framework \\\"${SIM_XC_FRAMEWORK_DIR}\\\"") != null);
}

test "phase_entry packages generated headers and modulemap into each framework slice" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "GENERATED_IOS_CANONICAL_HEADER") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "GENERATED_IOS_API_HEADER") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "GENERATED_IOS_FRAMEWORK_HEADER") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "GENERATED_IOS_MODULEMAP") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "prepare_framework_metadata()") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "Headers/WizigFFI.h") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "Modules/module.modulemap") != null);
}

test "phase_entry signs device framework outputs when code signing is enabled" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "EXPANDED_CODE_SIGN_IDENTITY") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "EXPANDED_CODE_SIGN_IDENTITY_NAME") == null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "${CODE_SIGN_IDENTITY:-}") == null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "missing Xcode-resolved signing identity") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "/usr/bin/codesign --force --sign") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "/usr/bin/codesign --verify --strict") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "CODE_SIGNING_ALLOWED") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "-headerpad_max_install_names") != null);
}

test "phase_entry validates device slice architectures for app-store safety" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "xcrun lipo -info") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "device framework unexpectedly contains simulator architectures") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "must contain arm64 architecture") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "PrivateFrameworks") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WIZIG_IOS_PRIVATE_SYMBOL_DENYLIST_REGEX") != null);
}

test "phase_entry assigns framework bundle identifier distinct from app" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "FRAMEWORK_BUNDLE_ID") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "PRODUCT_BUNDLE_IDENTIFIER") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, ".wizigffi") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "<string>dev.wizig.WizigFFI</string>") == null);
}

test "disableUserScriptSandboxingForAppTarget scopes rewrite to app target" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input =
        "/* Begin PBXNativeTarget section */\n" ++
        "\t\tAPP /* App */ = {\n" ++
        "\t\t\tbuildConfigurationList = APP_CFG_LIST /* Build configuration list for PBXNativeTarget \"App\" */;\n" ++
        "\t\t\tbuildPhases = (\n" ++
        "\t\t\t);\n" ++
        "\t\t\tproductType = \"com.apple.product-type.application\";\n" ++
        "\t\t};\n" ++
        "/* End PBXNativeTarget section */\n\n" ++
        "/* Begin XCBuildConfiguration section */\n" ++
        "\t\tAPP_DEBUG /* Debug */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Debug;\n" ++
        "\t\t};\n" ++
        "\t\tAPP_RELEASE /* Release */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Release;\n" ++
        "\t\t};\n" ++
        "\t\tTEST_DEBUG /* Debug */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Debug;\n" ++
        "\t\t};\n" ++
        "/* End XCBuildConfiguration section */\n\n" ++
        "/* Begin XCConfigurationList section */\n" ++
        "\t\tAPP_CFG_LIST /* Build configuration list for PBXNativeTarget \"App\" */ = {\n" ++
        "\t\t\tisa = XCConfigurationList;\n" ++
        "\t\t\tbuildConfigurations = (\n" ++
        "\t\t\t\tAPP_DEBUG /* Debug */,\n" ++
        "\t\t\t\tAPP_RELEASE /* Release */,\n" ++
        "\t\t\t);\n" ++
        "\t\t\tdefaultConfigurationIsVisible = 0;\n" ++
        "\t\t\tdefaultConfigurationName = Release;\n" ++
        "\t\t};\n" ++
        "/* End XCConfigurationList section */\n";

    const output = try disableUserScriptSandboxingForAppTarget(arena, input);

    const app_debug_start = std.mem.indexOf(u8, output, "APP_DEBUG /* Debug */ = {") orelse unreachable;
    const app_release_start = std.mem.indexOf(u8, output, "APP_RELEASE /* Release */ = {") orelse unreachable;
    const test_debug_start = std.mem.indexOf(u8, output, "TEST_DEBUG /* Debug */ = {") orelse unreachable;

    try std.testing.expect(std.mem.indexOfPos(u8, output, app_debug_start, "ENABLE_USER_SCRIPT_SANDBOXING = NO;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, app_release_start, "ENABLE_USER_SCRIPT_SANDBOXING = NO;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, test_debug_start, "ENABLE_USER_SCRIPT_SANDBOXING = YES;") != null);
}
