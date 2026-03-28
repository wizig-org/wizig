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

test {
    _ = @import("compatibility_tests.zig");
}

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
/// - `wire_format_version`: binary wire format revision for struct serialization.
///
/// ## Lifetime
/// The hash string is arena-owned by the allocator passed into builders.
pub const Metadata = struct {
    abi_version: u32,
    contract_hash_hex: []const u8,
    wire_format_version: u32,
};

/// Builds compatibility metadata from a full API spec.
pub fn buildMetadata(arena: std.mem.Allocator, spec: api.ApiSpec) !Metadata {
    const helpers = @import("render/helpers.zig");
    return .{
        .abi_version = ffi_abi_version,
        .contract_hash_hex = try computeContractHashHex(arena, spec),
        .wire_format_version = helpers.wire_format_version,
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
    hasher.update("wire:binary-v1");
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
