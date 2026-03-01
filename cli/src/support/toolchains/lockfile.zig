//! Toolchain lock-file generation.
//!
//! `wizig create` writes `.wizig/toolchain.lock.json` to capture the manifest
//! hash and detected host tool versions at scaffold time.
const std = @import("std");

const fs_util = @import("../fs.zig");
const probe = @import("probe.zig");
const types = @import("types.zig");

/// Probes host tools and writes project lock metadata JSON.
///
/// The emitted file is intentionally deterministic for a given manifest and
/// probe result set, except for creation timestamp.
pub fn writeProjectLock(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    manifest: types.ToolchainsManifest,
) !void {
    const tool_probes = probe.probeAll(arena, io, &manifest.doctor.tools);
    const created_at_unix = std.Io.Timestamp.now(io, .real).toSeconds();
    const json_text = try renderLockJson(arena, manifest, tool_probes, created_at_unix);

    const lock_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}.wizig{s}toolchain.lock.json",
        .{ project_root, std.fs.path.sep_str, std.fs.path.sep_str },
    );
    try fs_util.writeFileAtomically(io, lock_path, json_text);
}

/// Renders lock metadata as a JSON payload.
///
/// This function avoids generic JSON serializers so field ordering remains
/// stable and easy to diff in repository workflows.
fn renderLockJson(
    arena: std.mem.Allocator,
    manifest: types.ToolchainsManifest,
    tool_probes: [types.tool_count]types.ToolProbe,
    created_at_unix: i64,
) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);

    try out.appendSlice(arena, "{\n  \"schema_version\": 1,\n");
    try out.appendSlice(arena, "  \"manifest_schema_version\": ");
    try out.print(arena, "{d},\n", .{manifest.schema_version});
    try out.appendSlice(arena, "  \"manifest_sha256\": ");
    try appendEscapedString(arena, &out, manifest.manifest_sha256_hex);
    try out.appendSlice(arena, ",\n  \"created_at_unix\": ");
    try out.print(arena, "{d},\n", .{created_at_unix});
    try out.appendSlice(arena, "  \"tools\": {\n");

    for (manifest.doctor.tools, 0..) |policy, idx| {
        const result = tool_probes[idx];
        try out.appendSlice(arena, "    \"");
        try out.appendSlice(arena, types.toolJsonKey(policy.id));
        try out.appendSlice(arena, "\": {\n      \"required\": ");
        try out.appendSlice(arena, if (policy.required) "true" else "false");
        try out.appendSlice(arena, ",\n      \"min_version\": ");
        try appendEscapedString(arena, &out, policy.min_version);
        try out.appendSlice(arena, ",\n      \"detected\": ");
        try out.appendSlice(arena, if (result.present) "true" else "false");
        try out.appendSlice(arena, ",\n      \"detected_version\": ");
        if (result.version) |version| {
            try appendEscapedString(arena, &out, version);
        } else {
            try out.appendSlice(arena, "null");
        }
        try out.appendSlice(arena, "\n    }");
        if (idx + 1 < manifest.doctor.tools.len) {
            try out.appendSlice(arena, ",\n");
        } else {
            try out.appendSlice(arena, "\n");
        }
    }

    try out.appendSlice(arena, "  }\n}\n");
    return out.toOwnedSlice(arena);
}

/// Writes a JSON-escaped string value into `out`.
///
/// Only the minimal escape set required for lock metadata is handled because
/// all inputs are expected to be UTF-8 text from manifest or tool output.
fn appendEscapedString(
    arena: std.mem.Allocator,
    out: *std.ArrayList(u8),
    text: []const u8,
) !void {
    try out.append(arena, '"');
    for (text) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(arena, "\\\""),
            '\\' => try out.appendSlice(arena, "\\\\"),
            '\n' => try out.appendSlice(arena, "\\n"),
            '\r' => try out.appendSlice(arena, "\\r"),
            '\t' => try out.appendSlice(arena, "\\t"),
            else => try out.append(arena, ch),
        }
    }
    try out.append(arena, '"');
}

test "renderLockJson writes required top-level fields" {
    const tools = [_]types.ToolPolicy{
        .{ .id = .zig, .required = true, .min_version = "0.15.1" },
        .{ .id = .xcodebuild, .required = true, .min_version = "26.0.0" },
        .{ .id = .xcodegen, .required = false, .min_version = "2.39.0" },
        .{ .id = .java, .required = true, .min_version = "21.0.0" },
        .{ .id = .gradle, .required = true, .min_version = "9.2.1" },
        .{ .id = .adb, .required = true, .min_version = "1.0.41" },
    };
    const manifest: types.ToolchainsManifest = .{
        .schema_version = 1,
        .manifest_sha256_hex = "abc123",
        .doctor = .{ .strict_default = false, .tools = tools },
    };

    const probes = [_]types.ToolProbe{
        .{ .id = .zig, .present = true, .version = "0.16.0" },
        .{ .id = .xcodebuild, .present = true, .version = "26.1" },
        .{ .id = .xcodegen, .present = false, .version = null },
        .{ .id = .java, .present = true, .version = "21.0.3" },
        .{ .id = .gradle, .present = true, .version = "9.2.1" },
        .{ .id = .adb, .present = true, .version = "1.0.41" },
    };

    const json = try renderLockJson(std.testing.allocator, manifest, probes, 1_700_000_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"manifest_sha256\": \"abc123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"xcodegen\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"detected_version\": null") != null);
}
