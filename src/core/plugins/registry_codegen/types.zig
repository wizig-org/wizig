//! Shared registry data structures and lifecycle helpers.
const std = @import("std");
const PluginManifest = @import("../manifest.zig").PluginManifest;

/// Plugin file path paired with parsed manifest contents.
pub const PluginRecord = struct {
    manifest_path: []u8,
    manifest: PluginManifest,

    /// Releases owned path/manifest data.
    pub fn deinit(self: *PluginRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.manifest_path);
        self.manifest.deinit(allocator);
        self.* = undefined;
    }
};

/// In-memory registry of discovered plugins.
pub const Registry = struct {
    records: []PluginRecord,

    /// Releases all registry records and their owned allocations.
    pub fn deinit(self: *Registry, allocator: std.mem.Allocator) void {
        for (self.records) |*record| {
            record.deinit(allocator);
        }
        allocator.free(self.records);
        self.* = undefined;
    }
};
