const std = @import("std");

const phase_entry = @import("../ios_host_phase_entry.zig").phase_entry;

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

test "phase_entry signs embedded device frameworks with the app identity" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "--remove-signature") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "/usr/bin/codesign --force --sign") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "EXPANDED_CODE_SIGN_IDENTITY") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "CODE_SIGNING_ALLOWED") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "_CodeSignature/CodeResources") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "PLATFORM_NAME") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "-dynamic") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "--generate-entitlement-der") == null);
}

test "phase_entry validates device slice architectures for app-store safety" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "xcrun lipo -info") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "xcrun dyld_info -imports") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "device framework unexpectedly contains simulator architectures") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "must contain arm64 architecture") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "PrivateFrameworks") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WIZIG_IOS_PRIVATE_SYMBOL_DENYLIST_REGEX") != null);
}

test "phase_entry includes Mach-O page alignment fixup" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "fix_macho_text_page_alignment") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "python3") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "FEEDFACF") != null);
}

test "phase_entry contains only properly escaped quotes for pbxproj embedding" {
    const script_prefix = "shellScript = \"";
    const script_start_idx = std.mem.indexOf(u8, phase_entry, script_prefix) orelse unreachable;
    const content_start = script_start_idx + script_prefix.len;
    const script_end = std.mem.lastIndexOf(u8, phase_entry, "\";\n") orelse unreachable;
    const content = phase_entry[content_start..script_end];

    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        if (content[i] == '"' and (i == 0 or content[i - 1] != '\\')) {
            std.debug.print("unescaped quote at content offset {d}: ...{s}...\n", .{
                i,
                content[if (i >= 20) i - 20 else 0..@min(i + 20, content.len)],
            });
            try std.testing.expect(false);
        }
    }
}

test "phase_entry assigns framework bundle identifier distinct from app" {
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "FRAMEWORK_BUNDLE_ID") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "PRODUCT_BUNDLE_IDENTIFIER") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, ".wizigffi") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "<string>dev.wizig.WizigFFI</string>") == null);
}
