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
//!
//! Any semantic API change should update the hash.
const std = @import("std");

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

/// Builds compatibility metadata from a codegen API surface.
///
/// ## Inputs
/// `methods` and `events` are expected to be deterministic slices from the
/// codegen pipeline (already sorted/merged as needed by the caller).
///
/// ## Output
/// Returns a metadata struct that can be embedded directly into generated
/// Zig/Swift/Kotlin/JNI artifacts for host/runtime handshake validation.
pub fn buildMetadata(
    arena: std.mem.Allocator,
    namespace: []const u8,
    methods: anytype,
    events: anytype,
) !Metadata {
    return .{
        .abi_version = ffi_abi_version,
        .contract_hash_hex = try computeContractHashHex(arena, namespace, methods, events),
    };
}

/// Computes a lower-case SHA-256 hex digest for the API contract.
///
/// ## Determinism
/// The digest preserves declared slice order. Any method/event insertion,
/// removal, rename, or signature change updates the resulting hash.
pub fn computeContractHashHex(
    arena: std.mem.Allocator,
    namespace: []const u8,
    methods: anytype,
    events: anytype,
) ![]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("wizig-contract-hash-v1");
    hasher.update(&[_]u8{0});
    hasher.update(namespace);
    hasher.update(&[_]u8{0});

    for (methods) |method| {
        const input_tag = @tagName(method.input);
        const output_tag = @tagName(method.output);
        hasher.update("m:");
        hasher.update(method.name);
        hasher.update(":");
        hasher.update(input_tag);
        hasher.update(":");
        hasher.update(output_tag);
        hasher.update(&[_]u8{0});
    }

    for (events) |event| {
        const payload_tag = @tagName(event.payload);
        hasher.update("e:");
        hasher.update(event.name);
        hasher.update(":");
        hasher.update(payload_tag);
        hasher.update(&[_]u8{0});
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return arena.dupe(u8, &hex);
}

test "computeContractHashHex is stable for identical inputs" {
    const MethodType = struct {
        name: []const u8,
        input: enum { string, int, bool, void },
        output: enum { string, int, bool, void },
    };
    const EventType = struct {
        name: []const u8,
        payload: enum { string, int, bool, void },
    };

    const methods = [_]MethodType{
        .{ .name = "echo", .input = .string, .output = .string },
        .{ .name = "uptime", .input = .void, .output = .int },
    };
    const events = [_]EventType{
        .{ .name = "log", .payload = .string },
    };

    const first = try computeContractHashHex(std.testing.allocator, "dev.wizig.app", &methods, &events);
    defer std.testing.allocator.free(first);
    const second = try computeContractHashHex(std.testing.allocator, "dev.wizig.app", &methods, &events);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
}

test "computeContractHashHex changes when method signature changes" {
    const MethodType = struct {
        name: []const u8,
        input: enum { string, int, bool, void },
        output: enum { string, int, bool, void },
    };
    const EventType = struct {
        name: []const u8,
        payload: enum { string, int, bool, void },
    };

    const methods_a = [_]MethodType{
        .{ .name = "echo", .input = .string, .output = .string },
    };
    const methods_b = [_]MethodType{
        .{ .name = "echo", .input = .string, .output = .int },
    };
    const events = [_]EventType{
        .{ .name = "log", .payload = .string },
    };

    const first = try computeContractHashHex(std.testing.allocator, "dev.wizig.app", &methods_a, &events);
    defer std.testing.allocator.free(first);
    const second = try computeContractHashHex(std.testing.allocator, "dev.wizig.app", &methods_b, &events);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}
