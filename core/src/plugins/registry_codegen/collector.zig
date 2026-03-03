//! Plugin manifest discovery, sorting, and validation.
const std = @import("std");
const PluginManifest = @import("../manifest.zig").PluginManifest;
const PluginRecord = @import("types.zig").PluginRecord;
const Registry = @import("types.zig").Registry;

/// Collects plugin manifests from the given `plugins_dir`.
pub fn collectFromDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
) !Registry {
    var root_dir = try std.Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true });
    defer root_dir.close(io);

    var walker = try root_dir.walk(allocator);
    defer walker.deinit();

    var records = std.ArrayList(PluginRecord).empty;
    errdefer deinitRecordList(allocator, &records);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.eql(u8, entry.basename, "wizig-plugin.json")) continue;

        const manifest_text = try root_dir.readFileAlloc(io, entry.path, allocator, .limited(1024 * 1024));
        defer allocator.free(manifest_text);

        var manifest = try PluginManifest.parse(allocator, manifest_text);
        errdefer manifest.deinit(allocator);

        const manifest_path = try combineManifestPath(allocator, root_path, entry.path);
        errdefer allocator.free(manifest_path);

        try records.append(allocator, .{
            .manifest_path = manifest_path,
            .manifest = manifest,
        });
    }

    const records_slice = try records.toOwnedSlice(allocator);
    errdefer {
        for (records_slice) |*record| {
            record.deinit(allocator);
        }
        allocator.free(records_slice);
    }

    try sortAndValidate(records_slice);

    return .{ .records = records_slice };
}

/// Frees records accumulated during failed collection.
fn deinitRecordList(allocator: std.mem.Allocator, records: *std.ArrayList(PluginRecord)) void {
    for (records.items) |*record| {
        record.deinit(allocator);
    }
    records.deinit(allocator);
}

/// Ensures deterministic plugin order and duplicate-id rejection.
fn sortAndValidate(records: []PluginRecord) !void {
    std.mem.sort(PluginRecord, records, {}, lessById);

    var previous: ?[]const u8 = null;
    for (records) |record| {
        if (previous) |prev| {
            if (std.mem.eql(u8, prev, record.manifest.id)) {
                return error.DuplicatePluginId;
            }
        }
        previous = record.manifest.id;
    }
}

/// String ordering callback used for stable id sorting.
fn lessById(_: void, a: PluginRecord, b: PluginRecord) bool {
    return std.mem.order(u8, a.manifest.id, b.manifest.id) == .lt;
}

/// Returns root-relative manifest paths used in generated artifacts.
fn combineManifestPath(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    child_path: []const u8,
) ![]u8 {
    if (std.mem.eql(u8, root_path, ".")) {
        return allocator.dupe(u8, child_path);
    }
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ root_path, std.fs.path.sep_str, child_path });
}
