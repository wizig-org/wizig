const std = @import("std");

const ios_host_phase_entry = @import("../ios_host_phase_entry.zig");
const project_patcher = @import("project_patcher.zig");
const settings_patch = @import("settings_patch.zig");

const phase_name = ios_host_phase_entry.phase_name;
const phase_ref_line = ios_host_phase_entry.phase_ref_line;
const phase_entry = ios_host_phase_entry.phase_entry;

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

    const output = try project_patcher.patchProjectText(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, project_patcher.section_markers.begin_shell) != null);
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
        "\t\t\t\tCODE_SIGNING_ALLOWED = YES;\n" ++
        "\t\t\t\tCODE_SIGNING_REQUIRED = YES;\n" ++
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n" ++
        "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Debug;\n" ++
        "\t\t};\n" ++
        "\t\tAPP_RELEASE /* Release */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tCODE_SIGNING_ALLOWED = YES;\n" ++
        "\t\t\t\tCODE_SIGNING_REQUIRED = YES;\n" ++
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n" ++
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

    const output = try project_patcher.patchProjectText(arena, input);
    try std.testing.expectEqualStrings(input, output);
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

    const output = try settings_patch.disableUserScriptSandboxingForAppTarget(arena, input);

    const app_debug_start = std.mem.indexOf(u8, output, "APP_DEBUG /* Debug */ = {") orelse unreachable;
    const app_release_start = std.mem.indexOf(u8, output, "APP_RELEASE /* Release */ = {") orelse unreachable;
    const test_debug_start = std.mem.indexOf(u8, output, "TEST_DEBUG /* Debug */ = {") orelse unreachable;

    try std.testing.expect(std.mem.indexOfPos(u8, output, app_debug_start, "ENABLE_USER_SCRIPT_SANDBOXING = NO;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, app_release_start, "ENABLE_USER_SCRIPT_SANDBOXING = NO;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, test_debug_start, "ENABLE_USER_SCRIPT_SANDBOXING = YES;") != null);
}
