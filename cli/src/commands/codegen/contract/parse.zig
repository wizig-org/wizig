//! Contract parser entry points.
//!
//! This module keeps a small public surface and delegates format-specific
//! parsing to specialized submodules to keep each implementation focused and
//! maintainable.

const std = @import("std");
const api = @import("../model/api.zig");
const parse_zig = @import("parse_zig.zig");
const parse_json = @import("parse_json.zig");

/// Parses a Zig contract file (`wizig.api.zig`) into an `ApiSpec`.
pub fn parseApiSpecFromZig(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
    return parse_zig.parseApiSpecFromZig(arena, text);
}

/// Parses a JSON contract file (`wizig.api.json`) into an `ApiSpec`.
pub fn parseApiSpecFromJson(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
    return parse_json.parseApiSpecFromJson(arena, text);
}

test {
    _ = @import("parse_tests.zig");
}
