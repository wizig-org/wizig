//! PBX project text mutation helpers for the iOS host patch flow.
const std = @import("std");

const fs_util = @import("../../../support/fs.zig");
const ios_host_phase_entry = @import("../ios_host_phase_entry.zig");
const settings_patch = @import("settings_patch.zig");

const phase_name = ios_host_phase_entry.phase_name;
const phase_id = ios_host_phase_entry.phase_id;
const phase_ref_line = ios_host_phase_entry.phase_ref_line;
const phase_entry = ios_host_phase_entry.phase_entry;

/// Well-known PBX section markers used when inserting Wizig shell phases.
pub const section_markers = struct {
    pub const begin_shell = "/* Begin PBXShellScriptBuildPhase section */";
    pub const end_shell = "/* End PBXShellScriptBuildPhase section */";
    pub const begin_sources = "/* Begin PBXSourcesBuildPhase section */";
};

/// Patches one `.pbxproj` file on disk when its contents need updating.
pub fn patchProjectFile(
    arena: std.mem.Allocator,
    io: std.Io,
    pbx_path: []const u8,
) !bool {
    const original = try std.Io.Dir.cwd().readFileAlloc(io, pbx_path, arena, .limited(8 * 1024 * 1024));
    const patched = try patchProjectText(arena, original);
    if (std.mem.eql(u8, original, patched)) return false;
    return fs_util.writeFileIfChanged(arena, io, pbx_path, patched);
}

/// Applies all Wizig pbxproj rewrites to the provided project text.
pub fn patchProjectText(
    arena: std.mem.Allocator,
    text: []const u8,
) ![]const u8 {
    const with_section = try upsertShellSection(arena, text);
    const with_ref = try injectAppBuildPhaseReference(arena, with_section);
    const with_sandbox = try settings_patch.disableUserScriptSandboxingForAppTarget(arena, with_ref);
    return try settings_patch.enableAutomaticSigningForAppTarget(arena, with_sandbox);
}

/// Inserts or replaces the deterministic Wizig shell build phase block.
fn upsertShellSection(
    arena: std.mem.Allocator,
    text: []const u8,
) ![]const u8 {
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

/// Adds the Wizig build phase reference to the application target.
fn injectAppBuildPhaseReference(
    arena: std.mem.Allocator,
    text: []const u8,
) ![]const u8 {
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
