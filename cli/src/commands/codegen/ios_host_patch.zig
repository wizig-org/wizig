//! iOS host project patching for direct Xcode FFI builds.
//!
//! ## Problem
//! Direct Xcode builds do not run `wizig run`, so the simulator app bundle can
//! miss the per-app Wizig FFI dylib (`Frameworks/wizigffi`).
//!
//! ## Approach
//! This module patches generated host `.xcodeproj/project.pbxproj` files with a
//! deterministic `PBXShellScriptBuildPhase` that:
//! - builds the Zig FFI dylib for the active Apple SDK/arch,
//! - emits to `$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/wizigffi`,
//! - declares input/output paths for Xcode incremental dependency analysis.
//!
//! ## Safety
//! Patching is idempotent: if the phase already exists, no changes are written.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../../support/fs.zig");
const path_util = @import("../../support/path.zig");

/// Summary of iOS host project patching work performed in one codegen pass.
pub const PatchSummary = struct {
    /// Number of discovered `.xcodeproj` files scanned for migration.
    scanned_projects: usize = 0,
    /// Number of project files updated with new build phase wiring.
    patched_projects: usize = 0,
};

const phase_name = "Wizig Build iOS FFI";
const phase_id = "D0A0A0A0A0A0A0A0A0A0AF01";
const phase_ref_line = "\t\t\t\t" ++ phase_id ++ " /* " ++ phase_name ++ " */,\n";

const section_markers = struct {
    const begin_shell = "/* Begin PBXShellScriptBuildPhase section */";
    const end_shell = "/* End PBXShellScriptBuildPhase section */";
    const begin_sources = "/* Begin PBXSourcesBuildPhase section */";
};

const phase_entry =
    "\t\t" ++ phase_id ++ " /* " ++ phase_name ++ " */ = {\n" ++
    "\t\t\tisa = PBXShellScriptBuildPhase;\n" ++
    "\t\t\tbuildActionMask = 2147483647;\n" ++
    "\t\t\tfiles = (\n" ++
    "\t\t\t);\n" ++
    "\t\t\tinputPaths = (\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/generated/zig/WizigGeneratedFfiRoot.zig\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../.wizig/runtime/core/src/root.zig\",\n" ++
    "\t\t\t\t\"$(SRCROOT)/../lib/WizigGeneratedAppModule.zig\",\n" ++
    "\t\t\t);\n" ++
    "\t\t\tname = \"" ++ phase_name ++ "\";\n" ++
    "\t\t\toutputPaths = (\n" ++
    "\t\t\t\t\"$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/wizigffi\",\n" ++
    "\t\t\t);\n" ++
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n" ++
    "\t\t\tshellPath = /bin/sh;\n" ++
    "\t\t\tshellScript = \"set -eu\\n" ++
    "APP_ROOT=\\\"${SRCROOT}/..\\\"\\n" ++
    "GENERATED_ROOT=\\\"${APP_ROOT}/.wizig/generated/zig\\\"\\n" ++
    "RUNTIME_ROOT=\\\"${APP_ROOT}/.wizig/runtime\\\"\\n" ++
    "LIB_ROOT=\\\"${APP_ROOT}/lib\\\"\\n" ++
    "OUT_DIR=\\\"${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}\\\"\\n" ++
    "OUT_LIB=\\\"${OUT_DIR}/wizigffi\\\"\\n" ++
    "TMP_OUT_LIB=\\\"${TARGET_TEMP_DIR:-${TEMP_DIR:-/tmp}}/wizigffi\\\"\\n" ++
    "mkdir -p \\\"${OUT_DIR}\\\"\\n" ++
    "CACHE_BASE=\\\"${TARGET_TEMP_DIR:-${TEMP_DIR:-/tmp}}\\\"\\n" ++
    "ZIG_LOCAL_CACHE_DIR=\\\"${CACHE_BASE}/wizig-zig-local-cache\\\"\\n" ++
    "ZIG_GLOBAL_CACHE_DIR=\\\"${CACHE_BASE}/wizig-zig-global-cache\\\"\\n" ++
    "mkdir -p \\\"${ZIG_LOCAL_CACHE_DIR}\\\" \\\"${ZIG_GLOBAL_CACHE_DIR}\\\"\\n" ++
    "export ZIG_LOCAL_CACHE_DIR\\n" ++
    "export ZIG_GLOBAL_CACHE_DIR\\n" ++
    "ZIG_OPTIMIZE=\\\"${WIZIG_FFI_OPTIMIZE:-ReleaseFast}\\\"\\n" ++
    "if [ -z \\\"${WIZIG_FFI_OPTIMIZE:-}\\\" ]; then\\n" ++
    "  case \\\"${CONFIGURATION:-}\\\" in\\n" ++
    "    Debug|*Debug*) ZIG_OPTIMIZE=\\\"Debug\\\" ;;\\n" ++
    "  esac\\n" ++
    "fi\\n" ++
    "ARCH_VALUE=\\\"${CURRENT_ARCH:-}\\\"\\n" ++
    "if [ -z \\\"${ARCH_VALUE}\\\" ] || [ \\\"${ARCH_VALUE}\\\" = \\\"undefined_arch\\\" ]; then\\n" ++
    "  ARCH_VALUE=\\\"${NATIVE_ARCH_ACTUAL:-}\\\"\\n" ++
    "fi\\n" ++
    "if [ -z \\\"${ARCH_VALUE}\\\" ] || [ \\\"${ARCH_VALUE}\\\" = \\\"undefined_arch\\\" ]; then\\n" ++
    "  set -- ${ARCHS:-}\\n" ++
    "  ARCH_VALUE=\\\"${1:-}\\\"\\n" ++
    "fi\\n" ++
    "if [ \\\"${PLATFORM_NAME}\\\" = \\\"iphonesimulator\\\" ]; then\\n" ++
    "  case \\\"${ARCH_VALUE}\\\" in\\n" ++
    "    arm64) ZIG_TARGET=\\\"aarch64-ios-simulator\\\" ;;\\n" ++
    "    x86_64) ZIG_TARGET=\\\"x86_64-ios-simulator\\\" ;;\\n" ++
    "    *) echo \\\"error: unsupported iOS simulator arch '${ARCH_VALUE}' for Wizig FFI build\\\" >&2; exit 1 ;;\\n" ++
    "  esac\\n" ++
    "elif [ \\\"${PLATFORM_NAME}\\\" = \\\"iphoneos\\\" ]; then\\n" ++
    "  ZIG_TARGET=\\\"aarch64-ios\\\"\\n" ++
    "else\\n" ++
    "  echo \\\"error: unsupported Apple platform '${PLATFORM_NAME}' for Wizig FFI build\\\" >&2\\n" ++
    "  exit 1\\n" ++
    "fi\\n" ++
    "ZIG_BIN=\\\"${ZIG_BINARY:-}\\\"\\n" ++
    "if [ -z \\\"${ZIG_BIN}\\\" ]; then\\n" ++
    "  if command -v zig >/dev/null 2>&1; then\\n" ++
    "    ZIG_BIN=\\\"$(command -v zig)\\\"\\n" ++
    "  fi\\n" ++
    "fi\\n" ++
    "if [ -z \\\"${ZIG_BIN}\\\" ]; then\\n" ++
    "  for candidate in \\\"${HOME}/.zvm/master/zig\\\" \\\"${HOME}/.zvm/bin/zig\\\" \\\"${HOME}/.local/bin/zig\\\" \\\"/opt/homebrew/bin/zig\\\" \\\"/usr/local/bin/zig\\\"; do\\n" ++
    "    if [ -x \\\"${candidate}\\\" ]; then\\n" ++
    "      ZIG_BIN=\\\"${candidate}\\\"\\n" ++
    "      break\\n" ++
    "    fi\\n" ++
    "  done\\n" ++
    "fi\\n" ++
    "if [ -z \\\"${ZIG_BIN}\\\" ]; then\\n" ++
    "  echo \\\"error: zig is not installed or discoverable (PATH/ZIG_BINARY/common locations); required for Wizig iOS FFI build\\\" >&2\\n" ++
    "  exit 1\\n" ++
    "fi\\n" ++
    "\\\"${ZIG_BIN}\\\" build-lib -O\\\"${ZIG_OPTIMIZE}\\\" -fno-error-tracing -fno-unwind-tables -fstrip -target \\\"${ZIG_TARGET}\\\" --dep wizig_core --dep wizig_app -Mroot=\\\"${GENERATED_ROOT}/WizigGeneratedFfiRoot.zig\\\" -Mwizig_core=\\\"${RUNTIME_ROOT}/core/src/root.zig\\\" -Mwizig_app=\\\"${LIB_ROOT}/WizigGeneratedAppModule.zig\\\" --name wizigffi -dynamic -install_name @rpath/libwizigffi.dylib --sysroot \\\"${SDKROOT}\\\" -L/usr/lib -F/System/Library/Frameworks -lc -femit-bin=\\\"${TMP_OUT_LIB}\\\"\\n" ++
    "cp -f \\\"${TMP_OUT_LIB}\\\" \\\"${OUT_LIB}\\\"\\n\";\n" ++
    "\t\t};\n";

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
    return try injectAppBuildPhaseReference(arena, with_section);
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
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "TMP_OUT_LIB") != null);
    try std.testing.expect(std.mem.indexOf(u8, phase_entry, "WIZIG_FFI_OPTIMIZE") != null);
}
