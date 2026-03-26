//! Build-configuration rewrites for iOS host pbxproj patching.
const std = @import("std");

/// Disables user script sandboxing only for the application target configs.
///
/// Invariant: project-level and test target configurations remain untouched.
pub fn disableUserScriptSandboxingForAppTarget(
    arena: std.mem.Allocator,
    text: []const u8,
) ![]const u8 {
    const config_list_id = try resolveAppTargetConfigListId(text);
    var config_ids = try appTargetBuildConfigIds(arena, text, config_list_id);
    if (config_ids.items.len == 0) return error.InvalidPbxproj;

    var updated = text;
    for (config_ids.items) |config_id| {
        updated = try upsertUserScriptSandboxingNoForConfig(arena, updated, config_id);
    }
    return updated;
}

/// Enables Xcode automatic signing for the application target configs.
pub fn enableAutomaticSigningForAppTarget(
    arena: std.mem.Allocator,
    text: []const u8,
) ![]const u8 {
    const config_list_id = try resolveAppTargetConfigListId(text);
    var config_ids = try appTargetBuildConfigIds(arena, text, config_list_id);
    if (config_ids.items.len == 0) return error.InvalidPbxproj;

    var updated = text;
    for (config_ids.items) |config_id| {
        updated = try upsertAutomaticSigningForConfig(arena, updated, config_id);
    }
    return updated;
}

/// Resolves the application target's `XCConfigurationList` identifier.
fn resolveAppTargetConfigListId(text: []const u8) ![]const u8 {
    const app_product_type = "productType = \"com.apple.product-type.application\";";
    const app_idx = std.mem.indexOf(u8, text, app_product_type) orelse return error.InvalidPbxproj;
    const build_config_list_marker = "buildConfigurationList = ";
    const list_idx = std.mem.lastIndexOf(u8, text[0..app_idx], build_config_list_marker) orelse return error.InvalidPbxproj;
    const list_id_start = list_idx + build_config_list_marker.len;
    const list_id_end_rel = std.mem.indexOfAny(u8, text[list_id_start..], " ;\n\t") orelse return error.InvalidPbxproj;
    const config_list_id = std.mem.trim(u8, text[list_id_start .. list_id_start + list_id_end_rel], " \t");
    if (config_list_id.len == 0) return error.InvalidPbxproj;
    return config_list_id;
}

/// Collects the configuration ids listed by one `XCConfigurationList`.
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
        try out.append(arena, try arena.dupe(u8, trimmed[0..id_end]));
    }
    return out;
}

/// Ensures one config object sets `ENABLE_USER_SCRIPT_SANDBOXING = NO`.
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

/// Ensures one config object uses Xcode automatic signing.
///
/// This sets `CODE_SIGN_STYLE = Automatic`, enables signing, and removes empty
/// overrides that prevent Xcode from resolving the signing identity.
fn upsertAutomaticSigningForConfig(
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

    var result = try arena.dupe(u8, text);
    var delta: isize = 0;

    const removals = [_][]const u8{
        "CODE_SIGNING_ALLOWED = NO;",
        "CODE_SIGNING_REQUIRED = NO;",
        "CODE_SIGN_IDENTITY = \"\";",
        "DEVELOPMENT_TEAM = \"\";",
    };
    for (removals) |pattern| {
        const search_start: usize = @intCast(@as(isize, @intCast(build_start)) + delta);
        const search_end: usize = @intCast(@as(isize, @intCast(build_end)) + delta);
        if (std.mem.indexOf(u8, result[search_start..search_end], pattern)) |rel| {
            var line_start = search_start + rel;
            while (line_start > 0 and result[line_start - 1] != '\n') : (line_start -= 1) {}

            var line_end = search_start + rel + pattern.len;
            while (line_end < result.len and result[line_end] != '\n') : (line_end += 1) {}
            if (line_end < result.len) line_end += 1;

            const removed_len = line_end - line_start;
            result = try std.fmt.allocPrint(arena, "{s}{s}", .{
                result[0..line_start],
                result[line_end..],
            });
            delta -= @intCast(removed_len);
        }
    }

    const required_settings = [_]struct { key: []const u8, value: []const u8 }{
        .{ .key = "CODE_SIGN_STYLE", .value = "Automatic" },
        .{ .key = "CODE_SIGNING_ALLOWED", .value = "YES" },
        .{ .key = "CODE_SIGNING_REQUIRED", .value = "YES" },
    };
    for (required_settings) |setting| {
        const search_start: usize = @intCast(@as(isize, @intCast(build_start)) + delta);
        const search_end: usize = @intCast(@as(isize, @intCast(build_end)) + delta);
        const desired = try std.fmt.allocPrint(arena, "{s} = {s};", .{ setting.key, setting.value });
        const key_prefix = try std.fmt.allocPrint(arena, "{s} = ", .{setting.key});

        if (std.mem.indexOf(u8, result[search_start..search_end], desired) != null) continue;

        if (std.mem.indexOf(u8, result[search_start..search_end], key_prefix)) |rel| {
            var line_start = search_start + rel;
            while (line_start > 0 and result[line_start - 1] != '\n') : (line_start -= 1) {}

            var line_end = search_start + rel;
            while (line_end < result.len and result[line_end] != '\n') : (line_end += 1) {}
            if (line_end < result.len) line_end += 1;

            const old_len = line_end - line_start;
            const new_line = try std.fmt.allocPrint(arena, "\t\t\t\t{s}\n", .{desired});
            result = try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
                result[0..line_start],
                new_line,
                result[line_end..],
            });
            delta += @as(isize, @intCast(new_line.len)) - @as(isize, @intCast(old_len));
        } else {
            const insert_pos: usize = @intCast(@as(isize, @intCast(build_end)) + delta);
            const new_line = try std.fmt.allocPrint(arena, "\t\t\t\t{s}\n", .{desired});
            result = try std.fmt.allocPrint(arena, "{s}{s}{s}", .{
                result[0..insert_pos],
                new_line,
                result[insert_pos..],
            });
            delta += @intCast(new_line.len);
        }
    }

    return result;
}
