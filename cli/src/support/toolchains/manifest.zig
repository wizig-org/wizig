//! Toolchains manifest loader.
//!
//! This parser reads the specific policy subset Wizig uses from
//! `toolchains.toml` and produces strongly typed doctor policy settings.
const std = @import("std");
const Io = std.Io;

const types = @import("types.zig");

/// Loads and parses `toolchains.toml` from the given SDK/workspace root.
///
/// The function also computes and stores a SHA-256 digest of the exact file
/// bytes so downstream lockfiles can record the precise policy snapshot used.
pub fn loadFromRoot(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    root: []const u8,
) !types.ToolchainsManifest {
    const manifest_path = try std.fmt.allocPrint(arena, "{s}{s}toolchains.toml", .{ root, std.fs.path.sep_str });
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, arena, .limited(256 * 1024)) catch |err| {
        try stderr.print("error: failed to read toolchains manifest '{s}': {s}\n", .{ manifest_path, @errorName(err) });
        return error.NotFound;
    };

    var manifest = defaultManifest();
    try parseToolchainsToml(arena, bytes, &manifest);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    manifest.manifest_sha256_hex = try arena.dupe(u8, &digest_hex);
    return manifest;
}

/// Creates a fully populated manifest skeleton used before parsing.
///
/// Every known tool is initialized with deterministic ordering so parser logic
/// can update fields by index without dynamic allocations.
fn defaultManifest() types.ToolchainsManifest {
    var tools: [types.tool_count]types.ToolPolicy = undefined;
    const ordered = types.orderedTools();
    for (ordered, 0..) |tool, idx| {
        tools[idx] = .{ .id = tool, .required = true, .min_version = "" };
    }

    return .{
        .schema_version = 0,
        .manifest_sha256_hex = "",
        .doctor = .{
            .strict_default = false,
            .tools = tools,
        },
    };
}

/// Parses the supported subset of toolchains TOML into `manifest`.
///
/// The parser intentionally accepts only the fields required by Wizig doctor
/// and lockfile features. Unknown sections and keys are ignored so policy files
/// can evolve without breaking older binaries.
fn parseToolchainsToml(
    arena: std.mem.Allocator,
    text: []const u8,
    manifest: *types.ToolchainsManifest,
) !void {
    var section: []const u8 = "";

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = stripInlineComment(raw_line);
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;

        if (line[0] == '[' and line[line.len - 1] == ']') {
            section = std.mem.trim(u8, line[1 .. line.len - 1], " \t");
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value_raw = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, section, "schema") and std.mem.eql(u8, key, "version")) {
            manifest.schema_version = try parseTomlU32(value_raw);
            continue;
        }

        if (std.mem.eql(u8, section, "doctor") and std.mem.eql(u8, key, "strict_default")) {
            manifest.doctor.strict_default = try parseTomlBool(value_raw);
            continue;
        }

        const tools_prefix = "doctor.tools.";
        if (std.mem.startsWith(u8, section, tools_prefix)) {
            const tool_name = section[tools_prefix.len..];
            const idx = toolIndexByName(tool_name) orelse continue;
            if (std.mem.eql(u8, key, "required")) {
                manifest.doctor.tools[idx].required = try parseTomlBool(value_raw);
            } else if (std.mem.eql(u8, key, "min_version")) {
                const value = try parseTomlString(value_raw);
                manifest.doctor.tools[idx].min_version = try arena.dupe(u8, value);
            }
        }
    }

    if (manifest.schema_version == 0) return error.InvalidManifest;
    for (manifest.doctor.tools) |tool| {
        if (tool.min_version.len == 0) return error.InvalidManifest;
    }
}

/// Removes trailing inline comments while respecting quoted strings.
fn stripInlineComment(raw: []const u8) []const u8 {
    var in_quote = false;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '"') {
            in_quote = !in_quote;
            continue;
        }
        if (!in_quote and raw[i] == '#') {
            return raw[0..i];
        }
    }
    return raw;
}

/// Parses a quoted TOML string value.
fn parseTomlString(value_raw: []const u8) ![]const u8 {
    if (value_raw.len < 2) return error.InvalidManifest;
    if (value_raw[0] != '"' or value_raw[value_raw.len - 1] != '"') return error.InvalidManifest;
    return value_raw[1 .. value_raw.len - 1];
}

/// Parses a TOML boolean (`true` or `false`).
fn parseTomlBool(value_raw: []const u8) !bool {
    if (std.mem.eql(u8, value_raw, "true")) return true;
    if (std.mem.eql(u8, value_raw, "false")) return false;
    return error.InvalidManifest;
}

/// Parses an unsigned 32-bit TOML integer.
fn parseTomlU32(value_raw: []const u8) !u32 {
    return std.fmt.parseInt(u32, value_raw, 10) catch error.InvalidManifest;
}

/// Resolves a manifest tool section name to its deterministic array index.
fn toolIndexByName(name: []const u8) ?usize {
    const ordered = types.orderedTools();
    for (ordered, 0..) |tool, idx| {
        if (std.mem.eql(u8, name, types.toolJsonKey(tool))) return idx;
    }
    return null;
}

test "parseToolchainsToml reads schema and doctor tools" {
    const text =
        "[schema]\n" ++
        "version = 1\n" ++
        "\n" ++
        "[doctor]\n" ++
        "strict_default = true\n" ++
        "\n" ++
        "[doctor.tools.zig]\n" ++
        "required = true\n" ++
        "min_version = \"0.15.1\"\n" ++
        "\n" ++
        "[doctor.tools.xcodebuild]\nrequired = true\nmin_version = \"26.0.0\"\n" ++
        "[doctor.tools.xcodegen]\nrequired = false\nmin_version = \"2.39.0\"\n" ++
        "[doctor.tools.java]\nrequired = true\nmin_version = \"21.0.0\"\n" ++
        "[doctor.tools.gradle]\nrequired = true\nmin_version = \"9.2.1\"\n" ++
        "[doctor.tools.adb]\nrequired = true\nmin_version = \"1.0.41\"\n";

    var manifest = defaultManifest();
    try parseToolchainsToml(std.testing.allocator, text, &manifest);
    try std.testing.expectEqual(@as(u32, 1), manifest.schema_version);
    try std.testing.expect(manifest.doctor.strict_default);

    const tools = manifest.doctor.tools;
    try std.testing.expectEqualStrings("0.15.1", tools[0].min_version);
    try std.testing.expect(!tools[2].required);
}
