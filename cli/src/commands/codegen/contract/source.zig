//! Contract source metadata and extension detection.

const std = @import("std");

pub const ApiContractSource = enum {
    zig,
    json,
};

pub const ResolvedApiContract = struct {
    path: []const u8,
    source: ApiContractSource,
};

pub fn apiSourceFromPath(path: []const u8) !ApiContractSource {
    if (std.mem.endsWith(u8, path, ".zig")) return .zig;
    if (std.mem.endsWith(u8, path, ".json")) return .json;
    return error.InvalidContract;
}
