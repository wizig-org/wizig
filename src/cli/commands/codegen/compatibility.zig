//! Compatibility metadata for generated FFI bindings.
//!
//! ## Goals
//! - Provide a stable ABI version constant for runtime handshake checks.
//! - Derive a deterministic contract hash from the generated API surface.
//! - Keep host and Zig layers synchronized without requiring manual versioning.
//!
//! ## Hash Model
//! The hash includes:
//! - a fixed schema/version seed
//! - namespace
//! - ordered methods (`name`, `input`, `output`)
//! - ordered events (`name`, `payload`)
//! - ordered struct definitions (`name`, fields)
//! - ordered enum definitions (`name`, variants)
//!
//! Any semantic API change should update the hash.
const std = @import("std");
const api = @import("model/api.zig");

/// Current generated FFI ABI version.
///
/// Increment this when generated FFI symbol signatures or compatibility
/// semantics change in a non-backward-compatible way.
pub const ffi_abi_version: u32 = 1;

/// Compatibility metadata embedded into generated Zig/host bindings.
///
/// ## Fields
/// - `abi_version`: numeric ABI generation identifier.
/// - `contract_hash_hex`: lower-case SHA-256 digest of API surface contract.
///
/// ## Lifetime
/// The hash string is arena-owned by the allocator passed into builders.
pub const Metadata = struct {
    abi_version: u32,
    contract_hash_hex: []const u8,
};

/// Builds compatibility metadata from a full API spec.
pub fn buildMetadata(arena: std.mem.Allocator, spec: api.ApiSpec) !Metadata {
    return .{
        .abi_version = ffi_abi_version,
        .contract_hash_hex = try computeContractHashHex(arena, spec),
    };
}

fn hashApiType(hasher: *std.crypto.hash.sha2.Sha256, value: api.ApiType) void {
    switch (value) {
        .string => hasher.update("string"),
        .int => hasher.update("int"),
        .bool => hasher.update("bool"),
        .void => hasher.update("void"),
        .user_struct => |name| {
            hasher.update("user_struct:");
            hasher.update(name);
        },
        .user_enum => |name| {
            hasher.update("user_enum:");
            hasher.update(name);
        },
    }
}

/// Computes a lower-case SHA-256 hex digest for the API contract.
pub fn computeContractHashHex(arena: std.mem.Allocator, spec: api.ApiSpec) ![]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("wizig-contract-hash-v1");
    hasher.update(&[_]u8{0});
    hasher.update(spec.namespace);
    hasher.update(&[_]u8{0});

    for (spec.methods) |method| {
        hasher.update("m:");
        hasher.update(method.name);
        hasher.update(":");
        hashApiType(&hasher, method.input);
        hasher.update(":");
        hashApiType(&hasher, method.output);
        hasher.update(&[_]u8{0});
    }

    for (spec.events) |event| {
        hasher.update("e:");
        hasher.update(event.name);
        hasher.update(":");
        hashApiType(&hasher, event.payload);
        hasher.update(&[_]u8{0});
    }

    for (spec.structs) |s| {
        hasher.update("s:");
        hasher.update(s.name);
        for (s.fields) |field| {
            hasher.update(":");
            hasher.update(field.name);
            hasher.update(":");
            hashApiType(&hasher, field.field_type);
        }
        hasher.update(&[_]u8{0});
    }

    for (spec.enums) |e| {
        hasher.update("enum:");
        hasher.update(e.name);
        for (e.variants) |variant| {
            hasher.update(":");
            hasher.update(variant);
        }
        hasher.update(&[_]u8{0});
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return arena.dupe(u8, &hex);
}

test "computeContractHashHex is stable for identical inputs" {
    const spec: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{
            .{ .name = "echo", .input = .string, .output = .string },
            .{ .name = "uptime", .input = .void, .output = .int },
        },
        .events = &.{
            .{ .name = "log", .payload = .string },
        },
    };

    const first = try computeContractHashHex(std.testing.allocator, spec);
    defer std.testing.allocator.free(first);
    const second = try computeContractHashHex(std.testing.allocator, spec);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
}

test "computeContractHashHex changes when method signature changes" {
    const spec_a: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "echo", .input = .string, .output = .string }},
        .events = &.{.{ .name = "log", .payload = .string }},
    };
    const spec_b: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "echo", .input = .string, .output = .int }},
        .events = &.{.{ .name = "log", .payload = .string }},
    };

    const first = try computeContractHashHex(std.testing.allocator, spec_a);
    defer std.testing.allocator.free(first);
    const second = try computeContractHashHex(std.testing.allocator, spec_b);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "computeContractHashHex changes when struct fields change" {
    const spec_a: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{.{ .name = "Profile", .fields = &.{
            .{ .name = "name", .field_type = .string },
        } }},
    };
    const spec_b: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{.{ .name = "Profile", .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "age", .field_type = .int },
        } }},
    };

    const first = try computeContractHashHex(std.testing.allocator, spec_a);
    defer std.testing.allocator.free(first);
    const second = try computeContractHashHex(std.testing.allocator, spec_b);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "computeContractHashHex changes when enum variants change" {
    const spec_a: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .enums = &.{.{ .name = "Color", .variants = &.{ "red", "green" } }},
    };
    const spec_b: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .enums = &.{.{ .name = "Color", .variants = &.{ "red", "green", "blue" } }},
    };

    const first = try computeContractHashHex(std.testing.allocator, spec_a);
    defer std.testing.allocator.free(first);
    const second = try computeContractHashHex(std.testing.allocator, spec_b);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "computeContractHashHex changes when user payload names change" {
    const spec_a: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "save", .input = .{ .user_struct = "ProfileA" }, .output = .void }},
        .events = &.{},
    };
    const spec_b: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "save", .input = .{ .user_struct = "ProfileB" }, .output = .void }},
        .events = &.{},
    };

    const first = try computeContractHashHex(std.testing.allocator, spec_a);
    defer std.testing.allocator.free(first);
    const second = try computeContractHashHex(std.testing.allocator, spec_b);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}
