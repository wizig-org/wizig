const std = @import("std");

const settings_patch = @import("settings_patch.zig");

test "enableAutomaticSigningForAppTarget replaces disabled signing with automatic" {
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
        "\t\t\t\tCODE_SIGNING_ALLOWED = NO;\n" ++
        "\t\t\t\tCODE_SIGNING_REQUIRED = NO;\n" ++
        "\t\t\t\tCODE_SIGN_IDENTITY = \"\";\n" ++
        "\t\t\t\tDEVELOPMENT_TEAM = \"\";\n" ++
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Debug;\n" ++
        "\t\t};\n" ++
        "\t\tAPP_RELEASE /* Release */ = {\n" ++
        "\t\t\tisa = XCBuildConfiguration;\n" ++
        "\t\t\tbuildSettings = {\n" ++
        "\t\t\t\tCODE_SIGNING_ALLOWED = NO;\n" ++
        "\t\t\t\tCODE_SIGNING_REQUIRED = NO;\n" ++
        "\t\t\t\tCODE_SIGN_IDENTITY = \"\";\n" ++
        "\t\t\t\tDEVELOPMENT_TEAM = \"\";\n" ++
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
        "/* End XCConfigurationList section */\n";

    const output = try settings_patch.enableAutomaticSigningForAppTarget(arena, input);

    try std.testing.expect(std.mem.indexOf(u8, output, "CODE_SIGNING_ALLOWED = NO;") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "CODE_SIGNING_REQUIRED = NO;") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "CODE_SIGN_IDENTITY = \"\";") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "DEVELOPMENT_TEAM = \"\";") == null);

    const debug_start = std.mem.indexOf(u8, output, "APP_DEBUG /* Debug */ = {") orelse unreachable;
    const release_start = std.mem.indexOf(u8, output, "APP_RELEASE /* Release */ = {") orelse unreachable;
    try std.testing.expect(std.mem.indexOfPos(u8, output, debug_start, "CODE_SIGN_STYLE = Automatic;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, debug_start, "CODE_SIGNING_ALLOWED = YES;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, debug_start, "CODE_SIGNING_REQUIRED = YES;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, release_start, "CODE_SIGN_STYLE = Automatic;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, release_start, "CODE_SIGNING_ALLOWED = YES;") != null);
    try std.testing.expect(std.mem.indexOfPos(u8, output, release_start, "CODE_SIGNING_REQUIRED = YES;") != null);
}

test "enableAutomaticSigningForAppTarget is idempotent when already automatic" {
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
        "\t\t\t\tCODE_SIGNING_ALLOWED = YES;\n" ++
        "\t\t\t\tCODE_SIGNING_REQUIRED = YES;\n" ++
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n" ++
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n" ++
        "\t\t\t};\n" ++
        "\t\t\tname = Debug;\n" ++
        "\t\t};\n" ++
        "/* End XCBuildConfiguration section */\n\n" ++
        "/* Begin XCConfigurationList section */\n" ++
        "\t\tAPP_CFG_LIST /* Build configuration list for PBXNativeTarget \"App\" */ = {\n" ++
        "\t\t\tisa = XCConfigurationList;\n" ++
        "\t\t\tbuildConfigurations = (\n" ++
        "\t\t\t\tAPP_DEBUG /* Debug */,\n" ++
        "\t\t\t);\n" ++
        "\t\t\tdefaultConfigurationIsVisible = 0;\n" ++
        "\t\t\tdefaultConfigurationName = Release;\n" ++
        "\t\t};\n" ++
        "/* End XCConfigurationList section */\n";

    const output = try settings_patch.enableAutomaticSigningForAppTarget(arena, input);
    try std.testing.expectEqualStrings(input, output);
}
